# Bundle Generator Lambda

## Status

**Not Yet Implemented** - Complete code provided below

## Purpose

Lambda function that:
1. Queries PostgreSQL for authorization data
2. Builds OPA data bundle (JSON + manifest)
3. Uploads to S3 for OPA to consume
4. Runs on EventBridge schedule (e.g., every 5 minutes)

## Complete Lambda Code

### bundle-generator/lambda_function.py

Full implementation with database availability handling:

```python
"""
OPA Data Bundle Generator Lambda

Generates OPA data bundles from PostgreSQL database on a schedule.
Gracefully handles database unavailability during initial deployment.
"""
import json
import os
import sys
import time
import tarfile
import tempfile
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional

import boto3
import psycopg2
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
DB_SECRET_ARN = os.environ["DB_SECRET_ARN"]
S3_BUCKET = os.environ["S3_BUNDLE_BUCKET"]
S3_KEY_PREFIX = os.environ.get("S3_KEY_PREFIX", "opa/data/")

# AWS clients
secrets_manager = boto3.client("secretsmanager")
s3_client = boto3.client("s3")


def get_db_url_from_secrets() -> str:
    """Retrieve database URL from AWS Secrets Manager."""
    try:
        response = secrets_manager.get_secret_value(SecretId=DB_SECRET_ARN)
        secret = json.loads(response["SecretString"])
        
        return (
            f"postgresql://{secret['username']}:{secret['password']}"
            f"@{secret['host']}:{secret.get('port', 5432)}/{secret['dbname']}"
        )
    except ClientError as e:
        logger.error(f"Failed to retrieve database credentials: {e}")
        raise


def check_database_available(db_url: str, max_retries: int = 3) -> bool:
    """
    Check if database is available and ready.
    
    Returns True if database is accessible, False otherwise.
    Does NOT raise exceptions - gracefully handles unavailability.
    
    This is critical during initial deployment when Lambda may be created
    before the database is deployed by Ansible.
    """
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(db_url, connect_timeout=5)
            conn.close()
            logger.info("Database connection successful")
            return True
        except psycopg2.OperationalError as e:
            logger.warning(
                f"Database not available (attempt {attempt + 1}/{max_retries}): {e}"
            )
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)  # Exponential backoff: 1s, 2s, 4s
    
    return False


def query_authorization_data(db_url: str) -> Dict[str, List[Dict]]:
    """
    Query PostgreSQL for all authorization data.
    
    Returns dictionary with keys: users, tributaries, user_tributaries,
    resources, user_attributes.
    """
    conn = psycopg2.connect(db_url)
    cursor = conn.cursor()
    
    try:
        # Query users (minimal PII)
        cursor.execute("""
            SELECT id, email
            FROM "user"
            ORDER BY id
        """)
        users = [
            {"id": row[0], "email": row[1]}
            for row in cursor.fetchall()
        ]
        
        # Query tributaries
        cursor.execute("""
            SELECT id, name, description
            FROM tributary
            ORDER BY id
        """)
        tributaries = [
            {"id": row[0], "name": row[1], "description": row[2]}
            for row in cursor.fetchall()
        ]
        
        # Query user-tributary memberships
        cursor.execute("""
            SELECT user_id, tributary_id, granted_at
            FROM usertributary
            ORDER BY user_id, tributary_id
        """)
        user_tributaries = [
            {
                "user_id": row[0],
                "tributary_id": row[1],
                "granted_at": row[2].isoformat() if row[2] else None
            }
            for row in cursor.fetchall()
        ]
        
        # Query resources (exclude soft-deleted)
        cursor.execute("""
            SELECT id, tributary_id, resource_type, resource_identifier,
                   access_pattern, metadata
            FROM resource
            WHERE metadata->>'deleted' IS NULL
               OR metadata->>'deleted' = 'false'
            ORDER BY id
        """)
        resources = [
            {
                "id": row[0],
                "tributary_id": row[1],
                "resource_type": row[2],
                "resource_identifier": row[3],
                "access_pattern": row[4],
                "metadata": row[5] or {}
            }
            for row in cursor.fetchall()
        ]
        
        # Query user attributes
        cursor.execute("""
            SELECT user_id, attribute_key, attribute_value
            FROM userattribute
            ORDER BY user_id, attribute_key
        """)
        user_attributes = [
            {
                "user_id": row[0],
                "attribute_key": row[1],
                "attribute_value": row[2]
            }
            for row in cursor.fetchall()
        ]
        
        logger.info(
            f"Loaded {len(users)} users, {len(tributaries)} tributaries, "
            f"{len(resources)} resources, {len(user_attributes)} attributes"
        )
        
        return {
            "users": users,
            "tributaries": tributaries,
            "user_tributaries": user_tributaries,
            "resources": resources,
            "user_attributes": user_attributes
        }
        
    finally:
        cursor.close()
        conn.close()


def create_bundle(data: Dict[str, List[Dict]], revision: str) -> bytes:
    """
    Create OPA bundle tar.gz file.
    
    Args:
        data: Authorization data dictionary
        revision: Git commit hash or version string
    
    Returns:
        Bundle as bytes (tar.gz)
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        bundle_dir = Path(tmpdir) / "bundle"
        bundle_dir.mkdir()
        
        # Write data.json
        data_file = bundle_dir / "data.json"
        with open(data_file, 'w') as f:
            json.dump(data, f, indent=2)
        
        # Write manifest
        manifest = {
            "revision": revision,
            "roots": ["data"],
            "metadata": {
                "generated_at": datetime.utcnow().isoformat() + "Z",
                "source": "lambda-bundle-generator"
            }
        }
        manifest_file = bundle_dir / ".manifest"
        with open(manifest_file, 'w') as f:
            json.dump(manifest, f, indent=2)
        
        # Create tar.gz bundle
        bundle_file = Path(tmpdir) / "data-bundle.tar.gz"
        with tarfile.open(bundle_file, "w:gz") as tar:
            tar.add(bundle_dir, arcname=".")
        
        # Read bundle into memory
        with open(bundle_file, 'rb') as f:
            bundle_data = f.read()
        
        logger.info(f"Created bundle: {len(bundle_data)} bytes")
        return bundle_data


def upload_to_s3(bundle_data: bytes, bucket: str, key_prefix: str):
    """Upload bundle to S3."""
    timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    
    # Upload with timestamp (archive)
    archive_key = f"{key_prefix}archive/data-bundle-{timestamp}.tar.gz"
    s3_client.put_object(
        Bucket=bucket,
        Key=archive_key,
        Body=bundle_data,
        ContentType="application/gzip",
        Metadata={
            "generated-at": timestamp,
            "source": "lambda-bundle-generator"
        }
    )
    logger.info(f"Uploaded archive: s3://{bucket}/{archive_key}")
    
    # Upload as latest (OPA reads this)
    latest_key = f"{key_prefix}data-bundle-latest.tar.gz"
    s3_client.put_object(
        Bucket=bucket,
        Key=latest_key,
        Body=bundle_data,
        ContentType="application/gzip",
        Metadata={
            "generated-at": timestamp,
            "source": "lambda-bundle-generator"
        }
    )
    logger.info(f"Uploaded latest: s3://{bucket}/{latest_key}")


def lambda_handler(event, context):
    """
    Lambda handler: Generate OPA data bundle from PostgreSQL.
    
    Gracefully handles database unavailability (expected during initial deployment).
    """
    try:
        logger.info("Starting OPA bundle generation")
        
        # Get database URL
        db_url = get_db_url_from_secrets()
        
        # Check database availability
        if not check_database_available(db_url):
            logger.warning(
                "Database not available - skipping bundle generation. "
                "This is expected during initial deployment. "
                "Bundle will be generated on next scheduled run."
            )
            return {
                "statusCode": 200,  # Not an error
                "body": json.dumps({
                    "status": "skipped",
                    "reason": "database_not_available",
                    "message": "Bundle generation will occur when database is ready",
                    "timestamp": datetime.utcnow().isoformat()
                })
            }
        
        # Query database
        logger.info("Querying database for authorization data")
        data = query_authorization_data(db_url)
        
        # Create bundle
        revision = context.aws_request_id  # Use request ID as revision
        bundle_data = create_bundle(data, revision)
        
        # Upload to S3
        upload_to_s3(bundle_data, S3_BUCKET, S3_KEY_PREFIX)
        
        logger.info("Bundle generation completed successfully")
        return {
            "statusCode": 200,
            "body": json.dumps({
                "status": "success",
                "bundle_size": len(bundle_data),
                "data_counts": {
                    "users": len(data["users"]),
                    "tributaries": len(data["tributaries"]),
                    "resources": len(data["resources"]),
                    "user_attributes": len(data["user_attributes"])
                },
                "timestamp": datetime.utcnow().isoformat(),
                "revision": revision
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error during bundle generation: {e}", exc_info=True)
        # Don't raise - return error response
        return {
            "statusCode": 500,
            "body": json.dumps({
                "status": "error",
                "error": str(e),
                "error_type": type(e).__name__,
                "timestamp": datetime.utcnow().isoformat()
            })
        }
```

### bundle-generator/requirements.txt

```txt
# Database access
psycopg2-binary==2.9.9

# AWS SDK
boto3==1.34.0

# Database ORM (matches cape-cod-db dependency)
# Version should be updated when cape-cod-db schema changes
cape-cod-db==0.2.0

# If cape-cod-db is not on PyPI, use git reference:
# cape-cod-db @ git+https://github.com/cape-ph/cape-cod-db.git@v0.2.0
```

## Critical Implementation Details

### Database Availability Handling

**CRITICAL**: This is the most important aspect of the Lambda implementation.

**Why**: Lambda is deployed by Pulumi BEFORE database is deployed by Ansible.

**Deployment Sequence**:
1. `pulumi up` - Creates Lambda, EventBridge schedule
2. `ansible-playbook` - Creates RDS, runs migrations
3. EventBridge may trigger Lambda between steps 1-2

**Lambda Behavior**:
- Check database connectivity with 3 retries, exponential backoff
- Return 200 (not error) if database unavailable
- Log "database_not_available" (expected during initial deployment)
- Wait for next scheduled run (no manual intervention)

**Testing**: Must test scenario where database is unreachable

## Data Query Logic

### Tables Queried

1. **user** - id, email (minimal PII)
2. **tributary** - id, name, description
3. **usertributary** - user_id, tributary_id, granted_at
4. **resource** - id, tributary_id, resource_type, resource_identifier, access_pattern, metadata
5. **userattribute** - user_id, attribute_key, attribute_value

### Soft-Delete Filtering

Resources with `metadata->>'deleted' = 'true'` are excluded from bundles.

## Bundle Structure

### Data Bundle Contents

```
data-bundle-latest.tar.gz
├── .manifest
└── data.json
```

**data.json** format:
```json
{
  "users": [...],
  "tributaries": [...],
  "user_tributaries": [...],
  "resources": [...],
  "user_attributes": [...]
}
```

**.manifest** format:
```json
{
  "revision": "abc123-request-id",
  "roots": ["data"],
  "metadata": {
    "generated_at": "2026-06-29T10:30:00Z",
    "source": "lambda-bundle-generator"
  }
}
```

## S3 Upload Strategy

Two uploads per generation:

1. **Archive**: `opa/data/archive/data-bundle-{timestamp}.tar.gz`
   - Timestamped for debugging/history
   - Retained based on S3 lifecycle policy

2. **Latest**: `opa/data/data-bundle-latest.tar.gz`
   - OPA polls this path
   - Overwritten on each generation

## Environment Variables

Set by Pulumi (see 06-pulumi-integration.md):

- `DB_SECRET_ARN` - Secrets Manager ARN for database credentials
- `S3_BUNDLE_BUCKET` - S3 bucket name (cape-meta-assets-{env})
- `S3_KEY_PREFIX` - Optional prefix (default: "opa/data/")

## Lambda Layer

Dependencies installed via Pulumi-managed Lambda Layer:
- psycopg2-binary
- boto3
- cape-cod-db

See 06-pulumi-integration.md for layer build process.

## Deployment

### Build Package
```bash
./scripts/build_lambda_package.sh v1.2.3
```

Produces: `dist/data-bundle-generator-v1.2.3.zip`

### Deploy via Pulumi
```bash
cd cape-cod
pulumi config set opa_bundle_generator_version v1.2.3
pulumi up
```

## Monitoring

### CloudWatch Logs

Watch for:
- "database_not_available" during initial deployments (expected)
- "Bundle generation completed successfully" (normal operation)
- Any errors or exceptions (investigate immediately)

### CloudWatch Metrics (Future)

- Bundle generation time (should be stable)
- Bundle size (should grow slowly)
- Database query time
- S3 upload time
- Failure rate (should be near zero)

## Schema Change Procedure

When cape-cod-db schema changes:

1. Update `bundle-generator/requirements.txt` with new cape-cod-db version
2. Modify `lambda_function.py` SQL queries to handle schema changes
3. Update tests to match new schema
4. Create new cape-opa release
5. Update Pulumi config to reference new release
6. Run `pulumi up` to deploy Lambda
7. Update this file (03-bundle-generator.md) with changes

See 09-deployment-workflows.md for complete procedure.

## Testing

See 08-testing.md for complete testing strategy.

**Unit tests** (future):
- Mock database queries
- Mock S3 uploads
- Test database availability handling
- Test bundle creation logic

**Integration tests** (future):
- Docker Compose with real PostgreSQL
- Test actual database queries
- Test actual bundle generation
- Test OPA can load bundle

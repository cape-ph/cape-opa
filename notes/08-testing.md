# Testing Strategy

## Overview

Testing approach is TBD based on team preferences and resources. This document presents three options with increasing coverage and complexity.

## Current State

**Implemented**: Minimal testing
- Basic OPA policy tests in CI
- No Lambda unit tests yet
- No integration tests

**Goal**: Evolve testing strategy as project matures

## Testing Options

### Option 1: Minimal Testing (MVP - Current)

**Scope**: Basic validation only

**Policy Tests**:
```bash
# Run OPA policy tests
cd policies
opa test . -v
```

**Lambda Tests**: None (manual testing in dev environment)

**Integration Tests**: None

**CI/CD**: GitHub Actions runs OPA tests only

**Pros**:
- Fast to implement
- Minimal overhead
- No additional infrastructure needed

**Cons**:
- Less confidence in changes
- Catches only syntax errors
- No testing of actual database queries
- Manual verification required

**Time Investment**: Already done

---

### Option 2: Unit Tests Only (Recommended Next Step)

**Scope**: Comprehensive unit testing with mocks

#### Policy Tests

Complete test coverage with OPA test framework:

```rego
# policies/tests/authorize_test.rego
package cape

test_allow_write_to_tributary_resource {
    allow with input as {
        "user": {"id": 1},
        "action": "write",
        "resource": {"path": "s3://bucket/eng/raw/file.csv"}
    } with data as test_data
}

test_deny_write_to_unauthorized_resource {
    not allow with input as {
        "user": {"id": 2},
        "action": "write",
        "resource": {"path": "s3://bucket/eng/raw/file.csv"}
    } with data as test_data
}

test_deny_quarantined_user {
    not allow with input as {
        "user": {"id": 3},
        "action": "write",
        "resource": {"path": "s3://bucket/ds/raw/file.csv"}
    } with data as test_data
}

test_admin_can_access_everything {
    allow with input as {
        "user": {"id": 99},
        "action": "write",
        "resource": {"path": "s3://bucket/any/path"}
    } with data as test_admin_data
}
```

#### Lambda Tests

Complete pytest suite with mocked dependencies:

```python
# bundle-generator/tests/test_lambda_handler.py
import pytest
from unittest.mock import Mock, patch, MagicMock
import json

from lambda_function import (
    lambda_handler,
    check_database_available,
    query_authorization_data,
    create_bundle,
    upload_to_s3
)


@pytest.fixture
def mock_context():
    """Mock Lambda context"""
    context = Mock()
    context.aws_request_id = "test-request-123"
    return context


@pytest.fixture
def mock_db_url():
    return "postgresql://test:test@localhost:5432/test_db"


def test_check_database_available_success(mock_db_url):
    """Test successful database connection"""
    with patch('psycopg2.connect') as mock_connect:
        mock_conn = Mock()
        mock_connect.return_value = mock_conn
        
        result = check_database_available(mock_db_url)
        
        assert result is True
        mock_connect.assert_called_once()
        mock_conn.close.assert_called_once()


def test_check_database_available_failure(mock_db_url):
    """Test database unavailable (critical for deployment)"""
    with patch('psycopg2.connect') as mock_connect:
        import psycopg2
        mock_connect.side_effect = psycopg2.OperationalError("Connection refused")
        
        result = check_database_available(mock_db_url, max_retries=2)
        
        assert result is False
        assert mock_connect.call_count == 2  # Retried


def test_lambda_handler_database_unavailable(mock_context):
    """Test Lambda gracefully handles database unavailability"""
    with patch('lambda_function.get_db_url_from_secrets') as mock_get_db:
        with patch('lambda_function.check_database_available') as mock_check_db:
            mock_get_db.return_value = "postgresql://test:test@localhost/db"
            mock_check_db.return_value = False
            
            response = lambda_handler({}, mock_context)
            
            assert response['statusCode'] == 200  # Not an error!
            body = json.loads(response['body'])
            assert body['status'] == 'skipped'
            assert body['reason'] == 'database_not_available'


def test_lambda_handler_success(mock_context):
    """Test successful bundle generation"""
    with patch('lambda_function.get_db_url_from_secrets') as mock_get_db:
        with patch('lambda_function.check_database_available') as mock_check_db:
            with patch('lambda_function.query_authorization_data') as mock_query:
                with patch('lambda_function.create_bundle') as mock_create:
                    with patch('lambda_function.upload_to_s3') as mock_upload:
                        mock_get_db.return_value = "postgresql://test:test@localhost/db"
                        mock_check_db.return_value = True
                        mock_query.return_value = {
                            "users": [{"id": 1}],
                            "tributaries": [{"id": 1}],
                            "user_tributaries": [],
                            "resources": [],
                            "user_attributes": []
                        }
                        mock_create.return_value = b"bundle_data"
                        
                        response = lambda_handler({}, mock_context)
                        
                        assert response['statusCode'] == 200
                        body = json.loads(response['body'])
                        assert body['status'] == 'success'
                        assert 'bundle_size' in body


def test_query_authorization_data(mock_db_url):
    """Test database query logic"""
    with patch('psycopg2.connect') as mock_connect:
        mock_conn = Mock()
        mock_cursor = Mock()
        mock_connect.return_value = mock_conn
        mock_conn.cursor.return_value = mock_cursor
        
        # Mock query results
        mock_cursor.fetchall.side_effect = [
            [(1, "user@example.com")],  # users
            [(1, "ENG", "Engineering")],  # tributaries
            [(1, 1, None)],  # user_tributaries
            [(1, 1, "s3", "s3://bucket/eng/", "write", {})],  # resources
            [(1, "user_status", "active")]  # user_attributes
        ]
        
        result = query_authorization_data(mock_db_url)
        
        assert len(result['users']) == 1
        assert len(result['tributaries']) == 1
        assert result['users'][0]['email'] == "user@example.com"


def test_create_bundle():
    """Test bundle creation"""
    data = {
        "users": [{"id": 1, "email": "test@example.com"}],
        "tributaries": [],
        "user_tributaries": [],
        "resources": [],
        "user_attributes": []
    }
    revision = "test-revision"
    
    bundle = create_bundle(data, revision)
    
    assert isinstance(bundle, bytes)
    assert len(bundle) > 0
    # Could test tarball structure here


# More tests...
```

**Test Fixtures**:
```python
# bundle-generator/tests/fixtures/test_data.py
TEST_DATA = {
    "users": [
        {"id": 1, "email": "alice@example.com"},
        {"id": 2, "email": "bob@example.com"}
    ],
    "tributaries": [
        {"id": 1, "name": "ENG"},
        {"id": 2, "name": "DS"}
    ],
    # ... more test data
}
```

**CI Integration**:
```yaml
# In .github/workflows/test.yml
- name: Run Lambda tests
  run: |
    cd bundle-generator
    pytest tests/ -v --cov=. --cov-report=term-missing
```

**Pros**:
- Good coverage without infrastructure
- Fast execution (seconds)
- Runs in CI/CD
- Tests critical database availability handling
- Mocks S3, Secrets Manager, database

**Cons**:
- Doesn't test actual database queries
- Doesn't test actual S3 uploads
- Mocks may not match real behavior

**Time Investment**: 1-2 days to implement

---

### Option 3: Full Integration Testing (Future)

**Scope**: End-to-end testing with real services

#### Test Environment

Docker Compose with real services:

```yaml
# tests/integration/docker-compose.yml
version: '3.8'
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: cape_test_db
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
    ports:
      - "5432:5432"
    volumes:
      - ./fixtures/init.sql:/docker-entrypoint-initdb.d/init.sql
  
  opa:
    image: openpolicyagent/opa:latest
    ports:
      - "8181:8181"
    command:
      - "run"
      - "--server"
      - "--log-level=debug"
    volumes:
      - ./bundles:/bundles
  
  localstack:
    image: localstack/localstack:latest
    ports:
      - "4566:4566"
    environment:
      - SERVICES=s3,secretsmanager
      - DEFAULT_REGION=us-east-1
```

#### Integration Test Script

```bash
#!/usr/bin/env bash
# tests/integration/test_end_to_end.sh

set -euo pipefail

echo "Starting integration test..."

# Start services
docker-compose up -d
sleep 10

# Wait for PostgreSQL
until pg_isready -h localhost -U test -d cape_test_db; do
  echo "Waiting for PostgreSQL..."
  sleep 2
done

# Load test data
psql -h localhost -U test -d cape_test_db -f fixtures/test_data.sql

# Create S3 bucket in LocalStack
aws --endpoint-url=http://localhost:4566 s3 mb s3://test-bucket

# Store DB secret in LocalStack Secrets Manager
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name test-db-secret \
  --secret-string '{"host":"postgres","port":5432,"dbname":"cape_test_db","username":"test","password":"test"}'

# Run Lambda locally (with LocalStack endpoints)
export DB_SECRET_ARN="test-db-secret"
export S3_BUNDLE_BUCKET="test-bucket"
export S3_KEY_PREFIX="opa/data/"
export AWS_ENDPOINT_URL="http://localhost:4566"
cd ../../bundle-generator
python3 -c "
import lambda_function
import os
os.environ['AWS_ENDPOINT_URL'] = 'http://localhost:4566'
context = type('Context', (), {'aws_request_id': 'test-123'})()
result = lambda_function.lambda_handler({}, context)
print(result)
"

# Download data bundle from LocalStack S3
aws --endpoint-url=http://localhost:4566 s3 cp \
  s3://test-bucket/opa/data/data-bundle-latest.tar.gz \
  /tmp/data-bundle.tar.gz

# Load policy bundle into OPA
tar -xzf ../../dist/policy-bundle-latest.tar.gz -C /tmp/policy-bundle/
curl -X PUT --data-binary @/tmp/policy-bundle \
  http://localhost:8181/v1/policies

# Load data bundle into OPA
curl -X PUT --data-binary @/tmp/data-bundle.tar.gz \
  http://localhost:8181/v1/data

# Test authorization decision
RESULT=$(curl -s -X POST http://localhost:8181/v1/data/cape/authorize \
  -H 'Content-Type: application/json' \
  -d '{
    "input": {
      "user": {"id": 1},
      "action": "write",
      "resource": {"path": "s3://test-bucket/eng/raw-uploads/"}
    }
  }')

echo "Authorization result: $RESULT"

# Verify result
if echo "$RESULT" | jq -e '.result.allow == true' > /dev/null; then
  echo "✓ Authorization test passed"
else
  echo "✗ Authorization test failed"
  exit 1
fi

# Cleanup
docker-compose down -v

echo "✓ Integration test completed successfully"
```

**Test Data Fixtures**:
```sql
-- tests/integration/fixtures/test_data.sql
INSERT INTO "user" (id, email) VALUES
  (1, 'alice@example.com'),
  (2, 'bob@example.com');

INSERT INTO tributary (id, name, description) VALUES
  (1, 'ENG', 'Engineering team'),
  (2, 'DS', 'Data Science team');

INSERT INTO usertributary (user_id, tributary_id) VALUES
  (1, 1),
  (2, 2);

INSERT INTO resource (id, tributary_id, resource_type, resource_identifier, access_pattern, metadata) VALUES
  (1, 1, 's3', 's3://test-bucket/eng/raw-uploads/', 'write', '{}'),
  (2, 1, 's3', 's3://test-bucket/eng/clean-uploads/', 'read', '{}');

INSERT INTO userattribute (user_id, attribute_key, attribute_value) VALUES
  (1, 'user_status', 'active'),
  (2, 'user_status', 'active');
```

**Running Integration Tests**:
```bash
cd tests/integration
./test_end_to_end.sh
```

**Pros**:
- High confidence in actual behavior
- Tests real database queries
- Tests real S3 uploads
- Tests OPA with actual bundles
- Catches integration issues

**Cons**:
- Slower (minutes)
- Requires Docker
- More complex setup
- Harder to debug
- Not suitable for CI (unless using CI containers)

**Time Investment**: 3-5 days to implement fully

---

## Recommendation: Phased Approach

### Phase 1: Minimal (Current)
- **Now**: Basic OPA policy tests in CI
- **Time**: Already done
- **Goal**: Catch syntax errors

### Phase 2: Unit Tests (Next Sprint)
- **When**: After initial implementation works
- **Time**: 1-2 days
- **Goal**: Comprehensive test coverage without infrastructure

### Phase 3: Integration (When Stable)
- **When**: Team has bandwidth, stability is critical
- **Time**: 3-5 days
- **Goal**: End-to-end confidence

## Testing Commands

### Run All Tests

```bash
# Policy tests
opa test policies/ -v

# Lambda unit tests
cd bundle-generator && pytest tests/ -v

# Integration tests (if implemented)
cd tests/integration && ./test_end_to_end.sh
```

### Coverage Reports

```bash
# Lambda coverage
cd bundle-generator
pytest tests/ --cov=. --cov-report=html
open htmlcov/index.html
```

### Watch Mode (Development)

```bash
# Auto-run tests on file change
cd bundle-generator
pytest-watch tests/
```

## Future Enhancements

1. **Performance testing**: Benchmark policy evaluation speed
2. **Load testing**: Test Lambda under high load
3. **Security testing**: Automated security scans
4. **Mutation testing**: Verify test quality
5. **Property-based testing**: Generate test cases automatically
6. **Chaos testing**: Test failure scenarios

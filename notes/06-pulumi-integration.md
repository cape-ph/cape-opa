# Pulumi Integration

## Overview

Pulumi (in cape-cod repository) manages:
- Lambda Function (opa-bundle-generator)
- Lambda Layer (cape-cod-db dependencies)
- EventBridge schedule (triggers Lambda)
- IAM roles and policies
- Exports for other stacks

**Location**: `cape-cod` repository (Pulumi IaC)

## Complete Lambda Definition

### File: cape-cod/capeinfra/opa_lambda.py

Complete Pulumi code for OPA bundle generator:

```python
"""
OPA Bundle Generator Lambda - Pulumi Definition

This Lambda is triggered by EventBridge on a schedule to generate
OPA data bundles from the PostgreSQL database.
"""
import json
import subprocess
from pathlib import Path
import pulumi
import pulumi_aws as aws

# Configuration
config = pulumi.Config()
opa_version = config.require("opa_bundle_generator_version")  # e.g., "v1.2.3"
cape_cod_db_version = config.require("cape_cod_db_version")    # e.g., "0.2.0"

# Existing resources (from other modules)
db_secret = pulumi.StackReference("database").require_output("db_secret_arn")
meta_assets_bucket = pulumi.StackReference("storage").require_output("meta_assets_bucket")

# IAM Role for Lambda
lambda_role = aws.iam.Role(
    "opa-bundle-generator-role",
    assume_role_policy=json.dumps({
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    })
)

# Attach AWS managed policy for basic Lambda execution
aws.iam.RolePolicyAttachment(
    "opa-bundle-generator-basic-execution",
    role=lambda_role.name,
    policy_arn="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
)

# Custom policy for Secrets Manager and S3 access
aws.iam.RolePolicy(
    "opa-bundle-generator-custom-policy",
    role=lambda_role.name,
    policy=pulumi.Output.all(db_secret, meta_assets_bucket).apply(
        lambda args: json.dumps({
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": ["secretsmanager:GetSecretValue"],
                    "Resource": args[0]
                },
                {
                    "Effect": "Allow",
                    "Action": ["s3:PutObject", "s3:PutObjectAcl"],
                    "Resource": f"arn:aws:s3:::{args[1]}/opa/data/*"
                }
            ]
        })
    )
)

# Lambda Layer: cape-cod-db
# Built on-the-fly from requirements.txt
layer_build_dir = Path("./lambda_layers/cape_cod_db")
layer_build_dir.mkdir(parents=True, exist_ok=True)

# Create requirements.txt for layer
(layer_build_dir / "requirements.txt").write_text(f"cape-cod-db=={cape_cod_db_version}\n")

# Build layer during pulumi up
subprocess.run(
    [
        "pip", "install",
        "-r", str(layer_build_dir / "requirements.txt"),
        "-t", str(layer_build_dir / "python")
    ],
    check=True
)

cape_cod_db_layer = aws.lambda_.LayerVersion(
    "cape-cod-db-layer",
    layer_name="cape-cod-db",
    code=pulumi.AssetArchive({
        "python": pulumi.FileArchive(str(layer_build_dir / "python"))
    }),
    compatible_runtimes=["python3.11"],
    description=f"cape-cod-db version {cape_cod_db_version}"
)

# Lambda Function
# Downloads code from cape-opa GitHub release
lambda_package_url = (
    f"https://github.com/cape-ph/cape-opa/releases/download/{opa_version}/"
    f"data-bundle-generator-{opa_version}.zip"
)

opa_bundle_lambda = aws.lambda_.Function(
    "opa-bundle-generator",
    name="opa-bundle-generator",
    runtime="python3.11",
    handler="lambda_function.lambda_handler",
    role=lambda_role.arn,
    code=pulumi.RemoteArchive(lambda_package_url),
    layers=[cape_cod_db_layer.arn],
    timeout=300,  # 5 minutes
    memory_size=512,
    environment={
        "variables": {
            "DB_SECRET_ARN": db_secret,
            "S3_BUNDLE_BUCKET": meta_assets_bucket,
            "S3_KEY_PREFIX": "opa/data/"
        }
    },
    tags={
        "component": "opa",
        "managed_by": "pulumi",
        "opa_version": opa_version
    }
)

# EventBridge Schedule
schedule_rule = aws.cloudwatch.EventRule(
    "opa-bundle-schedule",
    name="opa-bundle-generation",
    description="Trigger OPA data bundle generation",
    schedule_expression="rate(5 minutes)"  # Configurable
)

# Grant EventBridge permission to invoke Lambda
aws.lambda_.Permission(
    "opa-bundle-eventbridge-permission",
    action="lambda:InvokeFunction",
    function=opa_bundle_lambda.name,
    principal="events.amazonaws.com",
    source_arn=schedule_rule.arn
)

# EventBridge Target
aws.cloudwatch.EventTarget(
    "opa-bundle-schedule-target",
    rule=schedule_rule.name,
    arn=opa_bundle_lambda.arn
)

# Exports
pulumi.export("opa_bundle_lambda_name", opa_bundle_lambda.name)
pulumi.export("opa_bundle_lambda_arn", opa_bundle_lambda.arn)
pulumi.export("cape_cod_db_layer_arn", cape_cod_db_layer.arn)  # For other Lambdas
```

## Pulumi Configuration

### File: cape-cod/Pulumi.dev.yaml

Configuration for dev stack:

```yaml
config:
  cape:opa_bundle_generator_version: "v1.2.3"
  cape:cape_cod_db_version: "0.2.0"
  cape:opa_bundle_schedule: "rate(5 minutes)"  # Optional override
```

### File: cape-cod/Pulumi.prod.yaml

Configuration for prod stack:

```yaml
config:
  cape:opa_bundle_generator_version: "v1.2.3"
  cape:cape_cod_db_version: "0.2.0"
  cape:opa_bundle_schedule: "rate(10 minutes)"  # Less frequent in prod
```

## Update Procedures

### Update Lambda Code (New cape-opa Release)

When cape-opa releases new version:

```bash
cd cape-cod

# Update config
pulumi config set opa_bundle_generator_version v1.2.4

# Preview changes
pulumi preview

# Deploy
pulumi up
```

**What happens**:
- Pulumi downloads new Lambda package from GitHub
- Updates Lambda function code
- No changes to Layer, IAM, or EventBridge

**Time**: ~2-3 minutes

### Update Database Schema (New cape-cod-db Version)

When cape-cod-db releases new version:

```bash
cd cape-cod

# Update config
pulumi config set cape_cod_db_version 0.3.0

# Preview changes
pulumi preview

# Deploy
pulumi up
```

**What happens**:
- Pulumi rebuilds Lambda Layer with new cape-cod-db
- Updates Layer version
- Attaches new Layer to Lambda
- Lambda now has new schema

**Time**: ~5-10 minutes (depends on layer size)

### Update Both Simultaneously

```bash
cd cape-cod

# Update both
pulumi config set opa_bundle_generator_version v1.3.0
pulumi config set cape_cod_db_version 0.3.0

# Deploy
pulumi up
```

### Change Schedule Frequency

```bash
cd cape-cod

# Change to every 2 minutes
pulumi config set opa_bundle_schedule "rate(2 minutes)"

pulumi up
```

Or directly in Pulumi code:
```python
schedule_expression=config.get("opa_bundle_schedule") or "rate(5 minutes)"
```

## IAM Permissions

### Lambda Execution Role Policies

**AWS Managed Policy**:
- `AWSLambdaBasicExecutionRole` - CloudWatch Logs

**Custom Policy** (inline):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:region:account:secret:db-secret"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:PutObjectAcl"],
      "Resource": "arn:aws:s3:::cape-meta-assets-*/opa/data/*"
    }
  ]
}
```

### EventBridge Permissions

Lambda permission allows EventBridge to invoke:
```json
{
  "Action": "lambda:InvokeFunction",
  "Principal": "events.amazonaws.com",
  "SourceArn": "arn:aws:events:region:account:rule/opa-bundle-generation"
}
```

## Lambda Layer Details

### Why a Layer?

Benefits:
- **Reusable**: Other Lambdas can use same cape-cod-db layer
- **Separate concerns**: Database schema separate from Lambda code
- **Version control**: Layer version tracks cape-cod-db version
- **Smaller packages**: Lambda package doesn't include heavy dependencies

### Layer Structure

```
cape-cod-db-layer
└── python/
    ├── cape_cod_db/
    │   ├── __init__.py
    │   ├── models.py
    │   └── ...
    ├── sqlalchemy/
    ├── alembic/
    └── (other dependencies)
```

### Layer Build Process

1. Create temp directory: `lambda_layers/cape_cod_db/`
2. Write requirements.txt: `cape-cod-db==0.2.0`
3. Install to `python/` subdirectory: `pip install -r requirements.txt -t python/`
4. Zip as layer: `python/` directory becomes `/opt/python` in Lambda
5. Upload to AWS
6. Attach to Lambda

### Using Layer in Other Lambdas

```python
# In another Lambda Pulumi definition
my_lambda = aws.lambda_.Function(
    "my-other-lambda",
    # ...
    layers=[cape_cod_db_layer.arn],  # Reuse layer
    # ...
)
```

## EventBridge Schedule

### Schedule Expression Formats

**Rate expressions**:
- `rate(5 minutes)` - Every 5 minutes
- `rate(1 hour)` - Every hour
- `rate(1 day)` - Every day

**Cron expressions**:
- `cron(0 12 * * ? *)` - Every day at 12:00 PM UTC
- `cron(0/10 * * * ? *)` - Every 10 minutes
- `cron(0 0 * * ? *)` - Every day at midnight UTC

### Recommended Schedules

- **Dev**: `rate(5 minutes)` - Fast feedback
- **Staging**: `rate(10 minutes)` - Moderate frequency
- **Prod**: `rate(15 minutes)` or `cron(0/15 * * * ? *)` - Reduce load

### Disable Schedule

To temporarily disable:

```python
schedule_rule = aws.cloudwatch.EventRule(
    "opa-bundle-schedule",
    # ...
    state="DISABLED"  # Add this line
)
```

Or remove EventBridge target (Lambda still exists but not triggered).

## Exports

Pulumi exports for use by other stacks or Ansible:

```python
pulumi.export("opa_bundle_lambda_name", opa_bundle_lambda.name)
pulumi.export("opa_bundle_lambda_arn", opa_bundle_lambda.arn)
pulumi.export("cape_cod_db_layer_arn", cape_cod_db_layer.arn)
```

### Usage by Other Stacks

```python
# In another Pulumi stack
opa_stack = pulumi.StackReference("organization/cape-cod/dev")
layer_arn = opa_stack.require_output("cape_cod_db_layer_arn")

my_lambda = aws.lambda_.Function(
    "my-lambda",
    layers=[layer_arn],
    # ...
)
```

### Usage by Ansible

```yaml
# Retrieve Lambda name from Pulumi
- name: Get Lambda function name
  shell: |
    cd /path/to/cape-cod
    pulumi stack output opa_bundle_lambda_name
  register: lambda_name

- name: Invoke Lambda
  command: >
    aws lambda invoke
    --function-name {{ lambda_name.stdout }}
    /tmp/response.json
```

## Monitoring and Debugging

### View Lambda Logs

```bash
# Via Pulumi
pulumi logs --follow --resource opa-bundle-generator

# Via AWS CLI
aws logs tail /aws/lambda/opa-bundle-generator --follow
```

### Invoke Lambda Manually

```bash
# Get function name
LAMBDA_NAME=$(pulumi stack output opa_bundle_lambda_name)

# Invoke
aws lambda invoke \
  --function-name $LAMBDA_NAME \
  --invocation-type RequestResponse \
  /tmp/response.json

# View response
cat /tmp/response.json | jq
```

### Check EventBridge Rule

```bash
aws events describe-rule --name opa-bundle-generation
aws events list-targets-by-rule --rule opa-bundle-generation
```

## Troubleshooting

### Lambda Times Out

Increase timeout in Pulumi code:
```python
opa_bundle_lambda = aws.lambda_.Function(
    # ...
    timeout=600,  # 10 minutes
    # ...
)
```

### Out of Memory

Increase memory:
```python
opa_bundle_lambda = aws.lambda_.Function(
    # ...
    memory_size=1024,  # 1 GB
    # ...
)
```

### Layer Too Large

Lambda layers have 250 MB limit (unzipped). If cape-cod-db dependencies exceed:

1. **Option A**: Split into multiple layers
2. **Option B**: Include dependencies in Lambda package (not layer)
3. **Option C**: Use Lambda container images instead

### GitHub Release Not Found

Error: `Failed to download from GitHub release`

**Causes**:
- Tag doesn't exist in cape-opa repo
- Release not published yet
- GitHub API rate limit (for public repos)
- Need authentication for private repos

**Solutions**:
```python
# For private repos, add GitHub token
code=pulumi.RemoteArchive(
    lambda_package_url,
    # Add auth header
    opts=pulumi.ResourceOptions(additional_secret_outputs=["code"])
)
```

## Future Enhancements

1. **Lambda versioning**: Use Lambda versions and aliases
2. **Canary deployments**: Gradual rollout of new Lambda code
3. **CloudWatch alarms**: Alert on Lambda failures
4. **X-Ray tracing**: Distributed tracing for debugging
5. **VPC integration**: Run Lambda in VPC for database security
6. **Reserved concurrency**: Prevent Lambda from overwhelming database
7. **Dead letter queue**: Capture failed invocations
8. **Layer caching**: Cache built layers for faster deployments

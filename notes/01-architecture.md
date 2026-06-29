# Architecture

## High-Level System Design

```
┌─────────────────────────────────────────────────────────────┐
│                  S3: cape-meta-assets-{env}                 │
│                                                               │
│  opa/                                                        │
│  ├── policies/                                              │
│  │   ├── policy-bundle-v1.2.3.tar.gz  (Ansible deployed)   │
│  │   └── policy-bundle-latest.tar.gz                       │
│  ├── data/                                                  │
│  │   ├── data-bundle-latest.tar.gz    (Lambda generated)   │
│  │   └── archive/                                          │
│  │       └── data-bundle-2026-06-25T12:00:00Z.tar.gz      │
└─────────────────────────────────────────────────────────────┘
                    ▲                      ▲
                    │                      │
         ┌──────────┴──────────┐          │
         │                     │          │
    [Ansible]            [Pulumi]   [Scheduled λ]
    deploys policy       creates    generates data
    bundle to S3         Lambda     bundle from DB
                         resource   (EventBridge)
         │                     │          │
         │                     │          │
    ┌────▼─────────────────────▼──────────▼────┐
    │        OPA on EC2 (via custom AMI)        │
    │    Pre-configured to poll S3 bundles      │
    └───────────────────────────────────────────┘
```

## Data Flows

### 1. Policy Updates
Developer → cape-opa repo → GitHub release → Ansible → S3 → OPA

1. Developer commits Rego policy changes
2. Push tag triggers GitHub Actions
3. Actions builds policy bundle tarball
4. Actions creates GitHub release with artifact
5. Ansible playbook downloads release artifact
6. Ansible uploads to S3 (cape-meta-assets/opa/policies/)
7. OPA polls S3 and loads new policies

### 2. Data Updates
PostgreSQL → Lambda (scheduled) → S3 → OPA

1. EventBridge triggers Lambda on schedule (e.g., every 5 minutes)
2. Lambda queries PostgreSQL for authorization data
3. Lambda builds data bundle (JSON + manifest in tar.gz)
4. Lambda uploads to S3 (cape-meta-assets/opa/data/)
5. OPA polls S3 and loads new data

### 3. Lambda Deployment
cape-opa release → Pulumi downloads → Lambda updated

1. Developer updates bundle-generator/lambda_function.py
2. Push tag triggers release (includes Lambda zip)
3. Pulumi config references new version
4. `pulumi up` downloads artifact from GitHub release
5. Pulumi updates Lambda function code

### 4. Schema Changes
cape-cod-db update → cape-opa bundle generator update → new release

1. Database schema changes in cape-cod-db
2. New cape-cod-db version published
3. Update bundle-generator/requirements.txt
4. Modify lambda_function.py to handle schema
5. Create new cape-opa release
6. Deploy via Pulumi

## Key Architectural Decisions

### Lambda Managed by Pulumi (NOT Ansible)
**Rationale**: Ensures clean tear-down with `pulumi destroy`

**Trade-off**: Some changes require Pulumi, others Ansible
- Pulumi: Lambda code, EventBridge schedule, IAM roles
- Ansible: Policy bundles, initial database setup, migrations

### Lambda Layer Built On-The-Fly
**Mechanism**: requirements.txt with cape-cod-db dependency

**Process**:
1. Pulumi reads requirements.txt
2. Builds Lambda Layer with dependencies
3. Attaches layer to Lambda function

**Benefits**: Reusable across Lambdas, version controlled, IaC managed

### S3 Bucket Structure
**Bucket**: Existing cape-meta-assets-{env} (NOT dedicated OPA bucket)

**Prefix**: `opa/` with subdirectories

**Rationale**: Consolidates runtime assets, follows existing patterns

### All-Dynamic Data (MVP)
**Policy Bundles**: Versioned in git, deployed via release process

**Data Bundles**: Generated dynamically, NOT in version control

**Seed Data**: Future consideration (auditing requirements unclear)

## Critical Implementation Constraints

### Database Availability Handling

**Problem**: Lambda deployed by Pulumi BEFORE database deployed by Ansible

**Deployment Order**:
1. Pulumi runs: Creates Lambda + EventBridge schedule
2. Ansible runs: Creates RDS + runs migrations
3. EventBridge may trigger Lambda between steps 1-2

**Solution**: Lambda MUST gracefully handle database unavailability
- Check database connectivity with retries
- Return 200 (not error) if database unavailable
- Log "database_not_available" (expected during initial deployment)
- Wait for next scheduled run

See notes/bundle-generator.md for implementation details.

## Component Responsibilities

### This Repository (cape-opa)
- OPA policies (Rego source code)
- Policy tests
- Lambda source code
- Lambda tests
- Build scripts
- GitHub Actions

**Produces**: policy-bundle-v{version}.tar.gz, data-bundle-generator-v{version}.zip

### cape-cod (Pulumi)
- OPA EC2 instance (custom AMI)
- Lambda Layer (cape-cod-db)
- Lambda Function (opa-bundle-generator)
- EventBridge schedule
- S3 bucket (cape-meta-assets)
- IAM roles

### cape-cod-env (Ansible)
- Database migrations (cape-cod-db)
- Download policy bundles from GitHub releases
- Upload policy bundles to S3
- Optionally trigger Lambda for initial data bundle

### cape-cod-db
- SQLModel schema definitions
- Alembic migrations
- Python package (PyPI or GitHub)

**Does NOT know about cape-opa** (one-way dependency)

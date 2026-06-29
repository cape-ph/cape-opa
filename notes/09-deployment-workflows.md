# Deployment Workflows

## Overview

Five complete deployment scenarios covering different change types. Each workflow specifies exact commands, tools used, and expected time.

## Workflow 1: Initial Setup (First-Time Deployment)

**Scenario**: Fresh environment deployment

**Prerequisites**:
- cape-cod-db repo exists with migrations
- cape-opa repo restructured per specification
- cape-cod Pulumi configured
- cape-cod-env Ansible configured

**Steps**:

```bash
# 1. Create cape-opa release
cd cape-opa
git tag v1.0.0 -m "Initial release"
git push --tags
# GitHub Actions builds and releases artifacts

# 2. Deploy infrastructure (Pulumi)
cd cape-cod
pulumi config set opa_bundle_generator_version v1.0.0
pulumi config set cape_cod_db_version 0.2.0
pulumi up
# Creates: Lambda, EventBridge, Layer, S3 bucket

# 3. Deploy environment (Ansible)
cd cape-cod-env
# Update group_vars/all.yml: opa_version: "v1.0.0"
ansible-playbook site.yml
# - Runs DB migrations
# - Uploads policy bundle to S3

# 4. Verify
# - Check CloudWatch logs for Lambda execution
# - Check S3 for data-bundle-latest.tar.gz
# - Check OPA server for loaded bundles
```

**Expected Behavior**:
- Lambda may log "database_not_available" initially (expected)
- Once DB is ready, Lambda generates bundle on next schedule
- OPA polls S3 and loads bundles

**Tools Used**: GitHub Actions + Pulumi + Ansible

**Time**: ~30-45 minutes

---

## Workflow 2: Policy Changes Only

**Scenario**: Updated authorization rules, no Lambda code changes

**Steps**:

```bash
# 1. Update policies in cape-opa
cd cape-opa/policies/cape
# Edit authorize.rego or other policy files

# 2. Test locally
opa test policies/ -v

# 3. Commit and release
git add policies/
git commit -m "Add new authorization rule for X"
git tag v1.0.1 -m "Add new authorization rule"
git push --tags

# 4. Deploy via Ansible
cd cape-cod-env
# Update group_vars: opa_version: "v1.0.1"
ansible-playbook deploy_opa_bundles.yml

# 5. Verify
# Check S3 for new policy bundle
# Check OPA logs for bundle reload
```

**Tools Used**: Ansible only (Pulumi not touched)

**Time**: ~5-10 minutes

**Verification**:
```bash
# Check S3
aws s3 ls s3://cape-meta-assets-dev/opa/policies/

# Check OPA logs
ssh opa-server
journalctl -u opa -f
```

---

## Workflow 3: Lambda Code Changes Only

**Scenario**: Bug fix or enhancement to bundle generator

**Steps**:

```bash
# 1. Update Lambda code in cape-opa
cd cape-opa/bundle-generator
# Edit lambda_function.py

# 2. Test locally (if integration tests exist)
pytest tests/

# 3. Commit and release
git add bundle-generator/
git commit -m "Fix bundle generation for empty tributaries"
git tag v1.0.2 -m "Fix empty tributary handling"
git push --tags

# 4. Deploy via Pulumi
cd cape-cod
pulumi config set opa_bundle_generator_version v1.0.2
pulumi up
# Downloads new Lambda package, updates function

# 5. Verify
# Check CloudWatch logs for next execution
# Verify bundle generation succeeds
```

**Tools Used**: Pulumi only (Ansible not touched)

**Time**: ~10-15 minutes

**Verification**:
```bash
# Check Lambda logs
aws logs tail /aws/lambda/opa-bundle-generator --follow

# Manual trigger
aws lambda invoke \
  --function-name opa-bundle-generator \
  /tmp/response.json
cat /tmp/response.json | jq
```

---

## Workflow 4: Database Schema Changes

**Scenario**: cape-cod-db adds new table or field

**Steps**:

```bash
# 1. Update cape-cod-db schema
cd cape-cod-db
# Modify models.py
alembic revision --autogenerate -m "Add new field"
git commit -m "Add tributary metadata field"
git tag v0.3.0
git push --tags
# Publish to PyPI (if applicable)

# 2. Update cape-opa bundle generator
cd cape-opa/bundle-generator
# Update requirements.txt: cape-cod-db==0.3.0
# Modify lambda_function.py to query new field
git commit -m "Support cape-cod-db v0.3.0 schema"
git tag v1.0.3 -m "Support new tributary metadata"
git push --tags

# 3. Deploy database migration
cd cape-cod-env
ansible-playbook run_migrations.yml

# 4. Deploy Lambda with new schema support
cd cape-cod
pulumi config set cape_cod_db_version 0.3.0  # Rebuilds layer
pulumi config set opa_bundle_generator_version v1.0.3
pulumi up

# 5. Verify
# Lambda should now query new field
# Check generated bundle includes new data
```

**Tools Used**: Both Ansible (DB) and Pulumi (Lambda + Layer)

**Time**: ~20-30 minutes

**Critical**: Deploy DB migrations BEFORE deploying new Lambda code

**Order Matters**:
1. Migrate database (backward compatible if possible)
2. Deploy Lambda with new schema support
3. Data bundles now include new fields

---

## Workflow 5: Combined Update (Policies + Lambda + DB)

**Scenario**: Major feature requiring changes across all components

**Example**: Add new resource type (EC2 instances) to authorization system

**Steps**:

```bash
# 1. Update all components
# (cape-cod-db, cape-opa policies, cape-opa Lambda)

# 2. Release in order
cd cape-cod-db
# Add EC2 resource type to schema
git tag v0.3.1 && git push --tags

cd cape-opa
# Update policies for EC2 authorization
# Update Lambda to query EC2 resources
git tag v1.1.0 && git push --tags

# 3. Deploy in order: DB → Lambda → Policies
cd cape-cod-env
ansible-playbook run_migrations.yml

cd cape-cod
pulumi config set cape_cod_db_version 0.3.1
pulumi config set opa_bundle_generator_version v1.1.0
pulumi up

cd cape-cod-env
# Update group_vars: opa_version: v1.1.0
ansible-playbook deploy_opa_bundles.yml

# 4. Verify end-to-end
# Test authorization with new rules
curl -X POST http://opa-server:8181/v1/data/cape/authorize \
  -d '{
    "input": {
      "user": {"id": 1},
      "action": "describe",
      "resource": {"type": "ec2", "arn": "arn:aws:ec2:..."}
    }
  }'
```

**Tools Used**: Both Ansible and Pulumi

**Time**: ~30-45 minutes

**Deployment Order**:
1. Database schema changes (add new tables/fields)
2. Lambda code updates (query new schema)
3. Policy updates (use new data)

---

## Rollback Procedures

### Rollback Policy Bundle

```bash
cd cape-cod-env

# Revert to previous version
ansible-playbook deploy_opa_bundles.yml \
  -e "opa_version=v1.0.0"
```

### Rollback Lambda

```bash
cd cape-cod

# Revert to previous version
pulumi config set opa_bundle_generator_version v1.0.1
pulumi up
```

### Rollback Database

```bash
cd cape-cod-db

# Use Alembic downgrade
alembic downgrade -1

# Or to specific revision
alembic downgrade abc123
```

---

## Verification Checklist

After any deployment:

### Check Lambda
- [ ] Lambda execution succeeds (CloudWatch Logs)
- [ ] Data bundle uploaded to S3
- [ ] No errors in logs
- [ ] Bundle size reasonable

### Check S3
- [ ] Policy bundle exists at correct path
- [ ] Data bundle exists at correct path
- [ ] Timestamps are recent
- [ ] File sizes are non-zero

### Check OPA
- [ ] OPA loaded new policy bundle
- [ ] OPA loaded new data bundle
- [ ] Test authorization query succeeds
- [ ] OPA logs show no errors

### Check Database
- [ ] Migrations applied successfully
- [ ] New tables/fields exist
- [ ] Data looks correct

---

## Common Issues

### Issue: GitHub Actions Release Failed

**Symptoms**: Tag pushed but no release created

**Check**:
```bash
gh run list --repo cape-ph/cape-opa
gh run view <run-id> --log
```

**Fix**: Re-run workflow or manually trigger

### Issue: Ansible Can't Download Bundle

**Symptoms**: `get_url` fails with 404

**Check**:
```bash
# Verify release exists
gh release view v1.2.3 --repo cape-ph/cape-opa

# Check artifact
curl -I https://github.com/cape-ph/cape-opa/releases/download/v1.2.3/policy-bundle-v1.2.3.tar.gz
```

**Fix**: Ensure release workflow completed, check artifact name

### Issue: Pulumi Can't Download Lambda Package

**Symptoms**: `RemoteArchive` fails

**Check**: Same as Ansible issue above

**Fix**: Verify GitHub release, check URL, ensure public access

### Issue: Lambda Timeout

**Symptoms**: Lambda times out generating bundle

**Check CloudWatch Logs**:
```bash
aws logs tail /aws/lambda/opa-bundle-generator --since 1h
```

**Fix**: Increase Lambda timeout in Pulumi code:
```python
timeout=600  # 10 minutes
```

### Issue: Database Migration Failed

**Symptoms**: Alembic error during migration

**Check**:
```bash
# View current revision
alembic current

# View migration history
alembic history

# Check database
psql -d cape_env_db -c "\dt"
```

**Fix**: Fix migration script, downgrade if needed, retry

---

## Monitoring Deployment Health

### Lambda Metrics

CloudWatch dashboard showing:
- Invocation count
- Error count
- Duration
- Bundle size over time

### OPA Metrics

Monitor OPA decision latency:
```bash
curl http://opa-server:8181/metrics
```

### S3 Metrics

Check bundle upload frequency and size:
```bash
aws s3api list-objects-v2 \
  --bucket cape-meta-assets-dev \
  --prefix opa/data/archive/
```

---

## Automation Opportunities

### Future: GitOps Workflow

1. **PR merged to main** → Automatically tag and release
2. **Release created** → Automatically update Pulumi config
3. **Pulumi updated** → Automatically run `pulumi up`
4. **Lambda deployed** → Automatically update Ansible vars
5. **Ansible vars updated** → Automatically run playbook

### Future: Blue/Green Deployments

1. Deploy new Lambda version as separate function
2. Run integration tests
3. Switch EventBridge to new Lambda
4. Keep old Lambda for rollback
5. Delete old Lambda after verification period

### Future: Canary Deployments

1. Deploy new OPA policies to 10% of servers
2. Monitor error rates
3. Gradually increase to 100%
4. Automatic rollback on errors

# Developer Procedures

## Making Policy Changes

Complete procedure for updating OPA policies:

```bash
# 1. Create feature branch
git checkout -b feature/add-ec2-authorization

# 2. Edit policies
cd policies/cape
vim authorize.rego

# 3. Update tests
cd ../tests
vim authorize_test.rego

# 4. Test locally
cd ../..
opa test policies/ -v

# 5. Format code
opa fmt policies/

# 6. Commit and push
git add policies/
git commit -m "Add EC2 instance authorization"
git push origin feature/add-ec2-authorization

# 7. Create PR
gh pr create --title "Add EC2 authorization" --body "..."

# 8. After review and merge
git checkout main
git pull

# 9. Release
git tag v1.1.0 -m "Add EC2 authorization"
git push --tags
# GitHub Actions builds and releases automatically

# 10. Update notes
# Edit notes/02-policies.md to reflect changes
git add notes/
git commit -m "Update policy documentation"
git push
```

---

## Making Lambda Changes

Complete procedure for updating bundle generator:

```bash
# 1. Create feature branch
git checkout -b fix/handle-null-metadata

# 2. Edit Lambda code
cd bundle-generator
vim lambda_function.py

# 3. Update requirements if needed
vim requirements.txt

# 4. Test locally (if tests exist)
pytest tests/ -v

# 5. Format code
black lambda_function.py

# 6. Lint code
ruff check .

# 7. Commit and push
git add bundle-generator/
git commit -m "Handle null metadata in resources"
git push origin fix/handle-null-metadata

# 8. Create PR
gh pr create --title "Fix null metadata handling" --body "..."

# 9. After review and merge
git checkout main
git pull

# 10. Release
git tag v1.0.4 -m "Fix null metadata handling"
git push --tags

# 11. Update notes
# Edit notes/03-bundle-generator.md
git add notes/
git commit -m "Update Lambda documentation"
git push
```

---

## Local Testing

### Test Policies

```bash
# Run all tests
cd policies
opa test . -v

# Run specific test
opa test . -v --run test_allow_write_to_tributary_resource

# Check syntax
opa check policies/

# Format check
opa fmt --check policies/

# Format and write
opa fmt -w policies/
```

### Test Lambda (Requires PostgreSQL)

```bash
# Set up test database
export DB_URL="postgresql://test:test@localhost:5432/cape_test_db"
psql -d cape_test_db -f ../cape-cod-db/fixtures/test/test_data.sql

# Run Lambda locally (mock AWS services)
cd bundle-generator
export DB_SECRET_ARN="mock-secret"
export S3_BUNDLE_BUCKET="mock-bucket"
python lambda_function.py

# Run unit tests
pytest tests/ -v

# With coverage
pytest tests/ -v --cov=. --cov-report=html
open htmlcov/index.html
```

### Build and Inspect Bundles

```bash
# Build policy bundle
./scripts/build_policy_bundle.sh test
tar -tzf dist/policy-bundle-test.tar.gz

# Build Lambda package
./scripts/build_lambda_package.sh test
unzip -l dist/data-bundle-generator-test.zip
```

### Integration Testing (if Docker Compose exists)

```bash
cd tests/integration
docker-compose up -d
./test_end_to_end.sh
docker-compose down
```

---

## Debugging

### Debug Policy Logic

```bash
# Use OPA REPL
opa run policies/

# Inside REPL
> data.cape.allow
> trace
> data.cape.allow with input as {"user": {"id": 1}, "action": "write", "resource": {"path": "s3://bucket/eng/"}}
```

### Debug Lambda Locally

```python
# Add to lambda_function.py
import pdb; pdb.set_trace()

# Run with debugger
python -m pdb lambda_function.py
```

### Debug in AWS

```bash
# Tail Lambda logs
aws logs tail /aws/lambda/opa-bundle-generator --follow

# Invoke manually with test event
aws lambda invoke \
  --function-name opa-bundle-generator \
  --payload '{}' \
  /tmp/response.json
cat /tmp/response.json | jq
```

---

## Dependency Updates

### Update cape-cod-db Dependency

When cape-cod-db releases new version:

```bash
cd cape-opa/bundle-generator

# Update requirements.txt
vim requirements.txt
# Change: cape-cod-db==0.3.0

# Test locally
pip install -r requirements.txt
pytest tests/

# Update Lambda code if schema changed
vim lambda_function.py

# Commit and release
git add bundle-generator/
git commit -m "Support cape-cod-db v0.3.0"
git tag v1.0.5
git push --tags
```

### Update OPA Version

To use newer OPA features:

```bash
# Update mise.toml
vim mise.toml
# Change: opa = "1.5.0"

# Install new version
mise install

# Test policies with new version
opa test policies/ -v

# Update GitHub Actions
vim .github/workflows/test.yml
# Update OPA download URL if needed
```

---

## Creating Releases

### Pre-Release Checklist

- [ ] All tests pass locally
- [ ] Code formatted and linted
- [ ] Notes updated (notes/ directory)
- [ ] CHANGELOG.md updated (if exists)
- [ ] Version bump is appropriate (semver)

### Semantic Versioning

Follow semver: MAJOR.MINOR.PATCH

- **MAJOR**: Breaking changes (v2.0.0)
  - Change policy decision format
  - Change Lambda environment variables
  - Remove deprecated features
  
- **MINOR**: New features, backward compatible (v1.1.0)
  - Add new policy rules
  - Add new Lambda capabilities
  - Add new resource types
  
- **PATCH**: Bug fixes, backward compatible (v1.0.1)
  - Fix policy logic errors
  - Fix Lambda bugs
  - Performance improvements

### Creating Release

```bash
# Ensure main is up to date
git checkout main
git pull

# Create tag with annotation
git tag v1.2.3 -m "Release v1.2.3: Add feature X, fix bug Y"

# Push tag
git push --tags

# GitHub Actions automatically:
# - Runs tests
# - Builds artifacts
# - Creates GitHub Release
# - Uploads artifacts

# Verify release
gh release view v1.2.3
```

### Release Notes Template

```markdown
## v1.2.3

### New Features
- Add EC2 instance authorization (#42)
- Support for IAM role-based access (#45)

### Bug Fixes
- Fix null metadata handling in Lambda (#43)
- Correct path matching for nested resources (#44)

### Improvements
- Reduce Lambda cold start time by 20% (#46)
- Add caching for database queries (#47)

### Breaking Changes
None

### Deployment Notes
- Requires cape-cod-db v0.3.0 or later
- Update Lambda timeout to 5 minutes (already in Pulumi code)
```

---

## Code Review Checklist

### For Policy Changes

- [ ] Tests added/updated
- [ ] Tests pass locally
- [ ] Policy logic is correct
- [ ] Path matching is secure (no regex DOS)
- [ ] Default deny preserved
- [ ] Reason messages are clear
- [ ] Performance acceptable (no infinite loops)
- [ ] Documentation updated

### For Lambda Changes

- [ ] Tests added/updated
- [ ] Tests pass locally
- [ ] Database queries are efficient
- [ ] S3 uploads are atomic
- [ ] Error handling is graceful
- [ ] Database unavailability handled
- [ ] Logging is appropriate
- [ ] Memory usage reasonable
- [ ] Documentation updated

---

## Branch Strategy

### Main Branch
- Always deployable
- Protected (requires PR)
- CI must pass

### Feature Branches
- `feature/add-ec2-auth`
- `feature/support-iam-roles`

### Fix Branches
- `fix/null-metadata`
- `fix/path-matching`

### Release Branches (Optional)
- `release/v1.2.x` - for backports

---

## Hotfix Procedure

Critical bug in production:

```bash
# 1. Create hotfix branch from latest release tag
git checkout v1.2.3
git checkout -b hotfix/critical-bug

# 2. Fix the bug
# ... make changes ...

# 3. Test
opa test policies/ -v  # or pytest

# 4. Commit
git commit -am "Fix critical authorization bypass"

# 5. Tag hotfix
git tag v1.2.4 -m "Hotfix: Fix authorization bypass"
git push --tags

# 6. Deploy immediately
cd cape-cod-env
ansible-playbook deploy_opa_bundles.yml -e "opa_version=v1.2.4"

# 7. Merge back to main
git checkout main
git merge hotfix/critical-bug
git push
```

---

## Environment Setup

### First Time Setup

```bash
# Clone repository
git clone https://github.com/cape-ph/cape-opa.git
cd cape-opa

# Install tools
mise install  # Installs OPA

# Install Python dependencies (for Lambda testing)
cd bundle-generator
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pip install -r requirements-dev.txt  # pytest, black, ruff, etc.

# Run tests
cd ..
opa test policies/ -v
cd bundle-generator && pytest tests/
```

### Daily Workflow

```bash
# Update main
git checkout main
git pull

# Create feature branch
git checkout -b feature/my-feature

# Make changes, commit frequently
git add .
git commit -m "Add feature X"

# Push and create PR
git push origin feature/my-feature
gh pr create
```

---

## Troubleshooting

### OPA Tests Fail

```bash
# Verbose output
opa test policies/ -v

# Show coverage
opa test policies/ --coverage

# Debug specific test
opa test policies/ -v --run test_name
```

### Lambda Tests Fail

```bash
# Run with verbose output
pytest tests/ -v -s

# Run specific test
pytest tests/test_lambda_handler.py::test_name -v

# Drop into debugger on failure
pytest tests/ --pdb
```

### Build Scripts Fail

```bash
# Check script permissions
chmod +x scripts/*.sh

# Run with bash -x for debugging
bash -x scripts/build_policy_bundle.sh test
```

---

## Communication

### Before Making Breaking Changes

1. Discuss in team meeting
2. Document in design doc
3. Get approval
4. Communicate to users

### After Release

1. Update deployment docs
2. Notify in Slack #cape-releases
3. Update project wiki
4. Monitor for issues

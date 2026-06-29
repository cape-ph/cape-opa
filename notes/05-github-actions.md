# GitHub Actions Workflows

## Overview

GitHub Actions automates:
- Testing on every commit/PR
- Building and releasing artifacts on tags
- Policy validation

## .github/workflows/release.yml

Complete release workflow (triggered on version tags):

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  test:
    name: Run Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Install OPA
        run: |
          curl -L -o opa https://openpolicyagent.org/downloads/latest/opa_linux_amd64
          chmod +x opa
          sudo mv opa /usr/local/bin/
      
      - name: Test OPA policies
        run: |
          opa test policies/ -v
      
      - name: Install Python dependencies
        run: |
          pip install pytest pytest-cov psycopg2-binary boto3
      
      - name: Test bundle generator
        run: |
          cd bundle-generator
          pytest tests/ -v
  
  build:
    name: Build Release Artifacts
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Get version from tag
        id: version
        run: echo "VERSION=${GITHUB_REF#refs/tags/}" >> $GITHUB_OUTPUT
      
      - name: Build policy bundle
        run: |
          chmod +x scripts/build_policy_bundle.sh
          ./scripts/build_policy_bundle.sh ${{ steps.version.outputs.VERSION }}
      
      - name: Build Lambda package
        run: |
          chmod +x scripts/build_lambda_package.sh
          ./scripts/build_lambda_package.sh ${{ steps.version.outputs.VERSION }}
      
      - name: Generate checksums
        run: |
          cd dist
          sha256sum * > checksums.txt
          cat checksums.txt
      
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            dist/policy-bundle-${{ steps.version.outputs.VERSION }}.tar.gz
            dist/data-bundle-generator-${{ steps.version.outputs.VERSION }}.zip
            dist/checksums.txt
          body: |
            Release ${{ steps.version.outputs.VERSION }}
            
            ## Artifacts
            
            - `policy-bundle-${{ steps.version.outputs.VERSION }}.tar.gz` - OPA policy bundle
            - `data-bundle-generator-${{ steps.version.outputs.VERSION }}.zip` - Lambda deployment package
            - `checksums.txt` - SHA256 checksums
            
            ## Deployment
            
            **Pulumi (Lambda):**
            ```
            pulumi config set opa_bundle_generator_version ${{ steps.version.outputs.VERSION }}
            pulumi up
            ```
            
            **Ansible (Policies):**
            ```yaml
            # group_vars/all.yml
            opa_version: "${{ steps.version.outputs.VERSION }}"
            ```
            ```
            ansible-playbook deploy_opa_bundles.yml
            ```
          draft: false
          prerelease: false
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**What it does**:

1. **Test job**:
   - Checkout code
   - Install Python 3.11
   - Install OPA binary
   - Run OPA policy tests (`opa test policies/ -v`)
   - Install Python test dependencies
   - Run Lambda unit tests (`pytest bundle-generator/tests/`)

2. **Build job** (runs after tests pass):
   - Checkout code
   - Extract version from tag (e.g., `v1.2.3`)
   - Build policy bundle (calls `build_policy_bundle.sh`)
   - Build Lambda package (calls `build_lambda_package.sh`)
   - Generate SHA256 checksums
   - Create GitHub Release with artifacts and deployment instructions

**Trigger**: Push tags matching `v*` pattern
**Required permission**: `contents: write` (to create releases)
**Artifacts uploaded**:
- policy-bundle-v{version}.tar.gz
- data-bundle-generator-v{version}.zip
- checksums.txt

## .github/workflows/test.yml

CI testing workflow (on every commit/PR):

```yaml
name: Test

on:
  push:
    branches:
      - main
      - develop
  pull_request:
    branches:
      - main
      - develop

jobs:
  test-policies:
    name: Test OPA Policies
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install OPA
        run: |
          curl -L -o opa https://openpolicyagent.org/downloads/latest/opa_linux_amd64
          chmod +x opa
          sudo mv opa /usr/local/bin/
      
      - name: Test policies
        run: |
          opa test policies/ -v
      
      - name: Format check
        run: |
          opa fmt --check policies/

  test-lambda:
    name: Test Lambda Function
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install pytest pytest-cov pytest-mock psycopg2-binary boto3
      
      - name: Run tests
        run: |
          cd bundle-generator
          pytest tests/ -v --cov=. --cov-report=term-missing
      
      - name: Check code formatting
        run: |
          pip install black
          black --check bundle-generator/

  lint:
    name: Lint Code
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Install linting tools
        run: |
          pip install ruff mypy
      
      - name: Run ruff
        run: |
          ruff check bundle-generator/
      
      - name: Run mypy
        run: |
          mypy bundle-generator/ --ignore-missing-imports
```

**What it does**:
- Runs on every push to main/develop
- Runs on every pull request
- Tests both OPA policies and Lambda code
- Checks code formatting and linting
- Does NOT create releases

## .github/workflows/validate.yml

Policy validation workflow:

```yaml
name: Validate

on:
  push:
    paths:
      - 'policies/**'
  pull_request:
    paths:
      - 'policies/**'

jobs:
  validate-policies:
    name: Validate Policy Syntax
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install OPA
        run: |
          curl -L -o opa https://openpolicyagent.org/downloads/latest/opa_linux_amd64
          chmod +x opa
          sudo mv opa /usr/local/bin/
      
      - name: Check syntax
        run: |
          opa check policies/
      
      - name: Format check
        run: |
          opa fmt --check policies/
      
      - name: Build test bundle
        run: |
          opa build -b policies/cape/ -o test-bundle.tar.gz
          tar -tzf test-bundle.tar.gz
```

**What it does**:
- Runs only when files in `policies/` change
- Validates Rego syntax
- Checks formatting
- Tests bundle building

## Workflow Triggers

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| release.yml | Tag push (v*) | Build and release artifacts |
| test.yml | Push/PR to main/develop | CI testing |
| validate.yml | Policy file changes | Syntax validation |

## Release Process

### Creating a Release

```bash
# 1. Update code, commit changes
git add .
git commit -m "Add new authorization rule"

# 2. Create and push tag
git tag v1.2.3 -m "Release v1.2.3: Add new authorization rule"
git push origin v1.2.3

# 3. GitHub Actions automatically:
#    - Runs tests
#    - Builds artifacts
#    - Creates GitHub Release
#    - Uploads artifacts
```

### Release Artifacts

After successful release, GitHub Release contains:

```
policy-bundle-v1.2.3.tar.gz
data-bundle-generator-v1.2.3.zip
checksums.txt
```

**checksums.txt** format:
```
abc123...  policy-bundle-v1.2.3.tar.gz
def456...  data-bundle-generator-v1.2.3.zip
```

### Download URLs

Artifacts accessible at:
```
https://github.com/cape-ph/cape-opa/releases/download/v1.2.3/policy-bundle-v1.2.3.tar.gz
https://github.com/cape-ph/cape-opa/releases/download/v1.2.3/data-bundle-generator-v1.2.3.zip
https://github.com/cape-ph/cape-opa/releases/download/v1.2.3/checksums.txt
```

Used by:
- Pulumi (downloads Lambda package)
- Ansible (downloads policy bundle)

## Secrets and Permissions

### Required Permissions

**GITHUB_TOKEN** (automatically provided):
- Read repository
- Write releases
- Write packages

No additional secrets required for basic workflow.

### Optional Secrets

For future enhancements:
- **AWS_ACCESS_KEY_ID** - Upload artifacts to S3
- **SLACK_WEBHOOK** - Notify on release
- **DOCKER_HUB_TOKEN** - Push integration test images

## Debugging Workflows

### View Workflow Runs

```bash
# List recent runs
gh run list

# View specific run
gh run view <run-id>

# View logs
gh run view <run-id> --log
```

### Re-run Failed Workflow

```bash
gh run rerun <run-id>
```

### Test Workflow Locally

Using [act](https://github.com/nektos/act):

```bash
# Test release workflow
act push --secret GITHUB_TOKEN=<token> -e .github/workflows/release.yml

# Test CI workflow
act push -e .github/workflows/test.yml
```

## Status Badges

Add to README.md:

```markdown
![Release](https://github.com/cape-ph/cape-opa/actions/workflows/release.yml/badge.svg)
![Test](https://github.com/cape-ph/cape-opa/actions/workflows/test.yml/badge.svg)
![Validate](https://github.com/cape-ph/cape-opa/actions/workflows/validate.yml/badge.svg)
```

## Future Enhancements

1. **Automated dependency updates**: Dependabot integration
2. **Security scanning**: CodeQL, Snyk, or Trivy
3. **Performance testing**: Benchmark policy evaluation
4. **Multi-environment releases**: Deploy to dev/staging/prod
5. **Release notes automation**: Generate from commit messages
6. **Slack notifications**: Notify team on releases
7. **Artifact signing**: Sign releases with GPG
8. **Docker image**: Build OPA image with policies pre-loaded

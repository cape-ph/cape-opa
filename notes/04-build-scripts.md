# Build Scripts

## Overview

Build scripts create release artifacts from source code:
- **policy bundles** (tar.gz) - OPA policies
- **Lambda packages** (zip) - Bundle generator deployment package

Scripts are executed by GitHub Actions on release (see 05-github-actions.md).

## scripts/build_policy_bundle.sh

Complete build script for OPA policy bundles:

```bash
#!/usr/bin/env bash
#
# Build OPA policy bundle from policies directory
#
# Usage: ./scripts/build_policy_bundle.sh <version>
# Example: ./scripts/build_policy_bundle.sh v1.2.3

set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 v1.2.3"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLICIES_DIR="$REPO_ROOT/policies"
OUTPUT_DIR="$REPO_ROOT/dist"

echo "Building OPA policy bundle version $VERSION"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create temporary bundle directory
BUNDLE_DIR=$(mktemp -d)
trap "rm -rf $BUNDLE_DIR" EXIT

# Copy policies
echo "Copying policy files..."
mkdir -p "$BUNDLE_DIR/cape"
cp "$POLICIES_DIR/cape"/*.rego "$BUNDLE_DIR/cape/"

# Generate manifest from template
echo "Generating manifest..."
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat "$POLICIES_DIR/.manifest.template" \
    | sed "s/\${GIT_COMMIT}/$GIT_COMMIT/g" \
    | sed "s/\${VERSION}/$VERSION/g" \
    | sed "s/\${BUILD_TIMESTAMP}/$BUILD_TIMESTAMP/g" \
    > "$BUNDLE_DIR/.manifest"

# Create tarball
BUNDLE_FILE="$OUTPUT_DIR/policy-bundle-$VERSION.tar.gz"
echo "Creating bundle: $BUNDLE_FILE"
tar -czf "$BUNDLE_FILE" -C "$BUNDLE_DIR" .

# Verify bundle
echo "Verifying bundle..."
tar -tzf "$BUNDLE_FILE" | head -10

echo "✓ Policy bundle created: $BUNDLE_FILE"
echo "  Size: $(du -h "$BUNDLE_FILE" | cut -f1)"
echo "  Revision: $GIT_COMMIT"
```

**What it does**:
1. Creates `dist/` directory
2. Creates temporary bundle directory
3. Copies all `.rego` files from `policies/cape/`
4. Generates `.manifest` from template (substitutes git commit, version, timestamp)
5. Creates `tar.gz` archive
6. Verifies bundle structure
7. Outputs to `dist/policy-bundle-v{version}.tar.gz`

**Variables substituted in manifest**:
- `${GIT_COMMIT}` - Current git commit hash
- `${VERSION}` - Version from argument (e.g., v1.2.3)
- `${BUILD_TIMESTAMP}` - UTC timestamp

## scripts/build_lambda_package.sh

Complete build script for Lambda deployment package:

```bash
#!/usr/bin/env bash
#
# Build Lambda deployment package
#
# Usage: ./scripts/build_lambda_package.sh <version>
# Example: ./scripts/build_lambda_package.sh v1.2.3

set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 v1.2.3"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_GEN_DIR="$REPO_ROOT/bundle-generator"
OUTPUT_DIR="$REPO_ROOT/dist"

echo "Building Lambda package version $VERSION"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create temporary package directory
PKG_DIR=$(mktemp -d)
trap "rm -rf $PKG_DIR" EXIT

# Install dependencies
echo "Installing dependencies..."
pip install -r "$BUNDLE_GEN_DIR/requirements.txt" -t "$PKG_DIR" --quiet

# Copy Lambda code
echo "Copying Lambda code..."
cp "$BUNDLE_GEN_DIR/lambda_function.py" "$PKG_DIR/"

# Create zip package
PACKAGE_FILE="$OUTPUT_DIR/data-bundle-generator-$VERSION.zip"
echo "Creating package: $PACKAGE_FILE"
(cd "$PKG_DIR" && zip -r -q "$PACKAGE_FILE" .)

# Verify package
echo "Verifying package..."
unzip -l "$PACKAGE_FILE" | grep "lambda_function.py"

echo "✓ Lambda package created: $PACKAGE_FILE"
echo "  Size: $(du -h "$PACKAGE_FILE" | cut -f1)"
```

**What it does**:
1. Creates `dist/` directory
2. Creates temporary package directory
3. Installs Python dependencies from `requirements.txt` into temp dir
4. Copies `lambda_function.py` into temp dir
5. Creates zip archive
6. Verifies `lambda_function.py` is present
7. Outputs to `dist/data-bundle-generator-v{version}.zip`

**Dependencies installed**:
- psycopg2-binary
- boto3
- cape-cod-db (or git reference)

## scripts/validate_bundle.sh

Future script for validating bundle structure:

```bash
#!/usr/bin/env bash
#
# Validate OPA bundle structure
#
# Usage: ./scripts/validate_bundle.sh <bundle.tar.gz>

set -euo pipefail

BUNDLE="${1:-}"
if [ -z "$BUNDLE" ]; then
    echo "Usage: $0 <bundle.tar.gz>"
    exit 1
fi

echo "Validating bundle: $BUNDLE"

# Check file exists
if [ ! -f "$BUNDLE" ]; then
    echo "Error: Bundle file not found"
    exit 1
fi

# Extract to temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

tar -xzf "$BUNDLE" -C "$TEMP_DIR"

# Check manifest exists
if [ ! -f "$TEMP_DIR/.manifest" ]; then
    echo "Error: .manifest not found"
    exit 1
fi

# Check manifest is valid JSON
if ! jq empty "$TEMP_DIR/.manifest" 2>/dev/null; then
    echo "Error: .manifest is not valid JSON"
    exit 1
fi

# Check cape directory exists (for policy bundles)
if [ -d "$TEMP_DIR/cape" ]; then
    echo "✓ Policy bundle structure valid"
    echo "  Policies:"
    find "$TEMP_DIR/cape" -name "*.rego" -exec basename {} \;
fi

# Check data.json exists (for data bundles)
if [ -f "$TEMP_DIR/data.json" ]; then
    echo "✓ Data bundle structure valid"
    if ! jq empty "$TEMP_DIR/data.json" 2>/dev/null; then
        echo "Error: data.json is not valid JSON"
        exit 1
    fi
fi

echo "✓ Bundle validation passed"
```

## scripts/test_integration.sh

Future script for integration testing:

```bash
#!/usr/bin/env bash
#
# Integration testing with Docker Compose
#
# Usage: ./scripts/test_integration.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$REPO_ROOT/tests/integration"

cd "$TEST_DIR"

echo "Starting integration test environment..."
docker-compose up -d

echo "Waiting for services to be ready..."
sleep 5

echo "Running integration tests..."
./test_end_to_end.sh

echo "Cleaning up..."
docker-compose down

echo "✓ Integration tests passed"
```

## Local Usage

### Build Policy Bundle

```bash
cd /path/to/cape-opa
./scripts/build_policy_bundle.sh v1.0.0
# Output: dist/policy-bundle-v1.0.0.tar.gz
```

### Build Lambda Package

```bash
cd /path/to/cape-opa
./scripts/build_lambda_package.sh v1.0.0
# Output: dist/data-bundle-generator-v1.0.0.zip
```

### Validate Bundle

```bash
./scripts/validate_bundle.sh dist/policy-bundle-v1.0.0.tar.gz
```

## CI/CD Usage

GitHub Actions calls these scripts (see 05-github-actions.md):

```yaml
- name: Build policy bundle
  run: |
    chmod +x scripts/build_policy_bundle.sh
    ./scripts/build_policy_bundle.sh ${{ steps.version.outputs.VERSION }}

- name: Build Lambda package
  run: |
    chmod +x scripts/build_lambda_package.sh
    ./scripts/build_lambda_package.sh ${{ steps.version.outputs.VERSION }}
```

## Output Artifacts

Both scripts output to `dist/` directory:

```
dist/
├── policy-bundle-v1.2.3.tar.gz
├── data-bundle-generator-v1.2.3.zip
└── checksums.txt  (generated by CI)
```

**policy-bundle-v{version}.tar.gz** structure:
```
.manifest
cape/
  authorize.rego
  user_writeable_resources.rego
  (other .rego files)
```

**data-bundle-generator-v{version}.zip** structure:
```
lambda_function.py
psycopg2/ (from requirements.txt)
boto3/ (from requirements.txt)
cape_cod_db/ (from requirements.txt)
(other dependencies)
```

## Error Handling

Scripts use `set -euo pipefail` for strict error handling:
- `e` - Exit on error
- `u` - Exit on undefined variable
- `o pipefail` - Exit if any command in pipeline fails

Temporary directories cleaned up via `trap`:
```bash
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT
```

## Prerequisites

### For build_policy_bundle.sh
- bash
- tar
- sed
- git (for commit hash)

### For build_lambda_package.sh
- bash
- Python 3.11+
- pip
- zip

### For validate_bundle.sh
- bash
- tar
- jq (JSON processor)

## Future Enhancements

1. **Checksums**: Generate SHA256 checksums automatically
2. **Signing**: Sign bundles for verification
3. **Size limits**: Warn if bundles exceed size thresholds
4. **Dependency caching**: Cache pip dependencies for faster builds
5. **Parallel builds**: Build policy and Lambda packages concurrently

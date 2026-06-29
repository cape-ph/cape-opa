#!/usr/bin/env bash

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

mkdir -p "$OUTPUT_DIR"

BUNDLE_DIR=$(mktemp -d)
trap "rm -rf $BUNDLE_DIR" EXIT

echo "Copying policy files..."
mkdir -p "$BUNDLE_DIR/cape"
cp "$POLICIES_DIR/cape"/*.rego "$BUNDLE_DIR/cape/"

echo "Generating manifest..."
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat "$POLICIES_DIR/.manifest.template" \
    | sed "s/\${GIT_COMMIT}/$GIT_COMMIT/g" \
    | sed "s/\${VERSION}/$VERSION/g" \
    | sed "s/\${BUILD_TIMESTAMP}/$BUILD_TIMESTAMP/g" \
    > "$BUNDLE_DIR/.manifest"

BUNDLE_FILE="$OUTPUT_DIR/policy-bundle-$VERSION.tar.gz"
echo "Creating bundle: $BUNDLE_FILE"
tar -czf "$BUNDLE_FILE" -C "$BUNDLE_DIR" .

echo "Verifying bundle..."
tar -tzf "$BUNDLE_FILE" | head -10

echo "✓ Policy bundle created: $BUNDLE_FILE"
echo "  Size: $(du -h "$BUNDLE_FILE" | cut -f1)"
echo "  Revision: $GIT_COMMIT"

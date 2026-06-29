# Project Overview

## Purpose

Cape OPA Policy Repository provides:
1. **OPA Policies**: Rego policies for resource-based authorization
2. **Data Bundle Generator**: Lambda that generates OPA data bundles from PostgreSQL
3. **Build Tooling**: Scripts and automation for bundle creation
4. **Release Artifacts**: Versioned policy bundles and Lambda packages

## Current State

**Status**: Early development / restructuring phase

**What exists**:
- `cape/capeallow.rego` - Simple allow-all policy for initial testing
- `.design/` directory - Complete implementation blueprints (NOT implemented yet)
- Basic repository structure

**What's planned** (per .design documents):
- Full authorization policies (authorize.rego, user_writeable_resources.rego, etc.)
- Lambda function for data bundle generation
- Build scripts (build_policy_bundle.sh, build_lambda_package.sh)
- GitHub Actions workflows (release.yml, test.yml)
- Integration with cape-cod (Pulumi) and cape-cod-env (Ansible)

## Key Concepts

**Policy Bundles**: OPA policies packaged as tar.gz files, deployed to S3
- Versioned in git
- Built on release
- Deployed by Ansible

**Data Bundles**: Authorization data (users, tributaries, resources) packaged for OPA
- Generated dynamically from PostgreSQL by Lambda
- NOT versioned in git
- Updated on schedule (EventBridge)

**S3 Structure** (cape-meta-assets-{env}):
```
opa/
├── policies/
│   ├── policy-bundle-v1.2.3.tar.gz  (Ansible deployed)
│   └── policy-bundle-latest.tar.gz
├── data/
│   ├── data-bundle-latest.tar.gz    (Lambda generated)
│   └── archive/
│       └── data-bundle-2026-06-25T12:00:00Z.tar.gz
```

## Roadmap

1. **Phase 1**: Implement core authorization policies
2. **Phase 2**: Build Lambda data bundle generator
3. **Phase 3**: Create build and release automation
4. **Phase 4**: Integrate with Pulumi (Lambda) and Ansible (policies)
5. **Phase 5**: End-to-end testing and deployment

## Dependencies

- **cape-cod-db**: Database schema (Python package)
- **cape-cod**: Pulumi infrastructure (Lambda, S3, OPA EC2)
- **cape-cod-env**: Ansible deployment automation
- **OPA**: Open Policy Agent (installed via mise)

## Testing

```bash
# Test policies
opa test cape/ -v

# Build policy bundle
opa build -b cape/ -o bundle.tar.gz

# Test Lambda (when implemented)
cd bundle-generator && pytest tests/
```

# Agent Instructions for cape-opa

## Project Context Enforcement

**MANDATORY: Context is NOT optional**

Before starting ANY work in this repository, you MUST:

1. **Load ALL context files**: Read every file in `notes/*.md` to understand the project
2. **Maintain context discipline**: Update relevant notes in the SAME session as code changes
3. **Verify before completion**: Check that context reflects current state before marking work complete

### Loading Protocol

```
At session start, read:
- notes/*.md (all files, in order)
```

### Maintenance Requirements

**CRITICAL**: Context updates are NOT separate tasks - they are PART of the work.

When you:
- Add/modify OPA policies → Update notes/02-policies.md
- Change Lambda code → Update notes/03-bundle-generator.md
- Modify build scripts → Update notes/04-build-scripts.md
- Update GitHub workflows → Update notes/05-github-actions.md
- Update integration points → Update notes/06-pulumi-integration.md or notes/07-ansible-integration.md

### Verification Checklist

Before marking work complete:
- [ ] All relevant notes/*.md files reflect changes made
- [ ] Architecture diagrams updated if structure changed
- [ ] Integration points documented if external contracts changed
- [ ] No stale information remains in context

**Work is INCOMPLETE without context updates.**

---

## Project Overview

This repository contains OPA (Open Policy Agent) authorization policies and data bundle generation for CAPE's attribute-based access control (ABAC) system.

### Key Components

1. **OPA Policies** (`policies/cape/`): Rego policies for authorization decisions ✅ IMPLEMENTED
2. **Policy Tests** (`policies/tests/`): Comprehensive test suite ✅ IMPLEMENTED
3. **Build Scripts** (`scripts/`): Bundle creation automation ✅ PARTIALLY IMPLEMENTED
4. **Bundle Generator Lambda** (`bundle-generator/`): Dynamic data bundle generation from PostgreSQL ❌ NOT YET IMPLEMENTED
5. **GitHub Actions** (`.github/workflows/`): Test and release automation ✅ IMPLEMENTED

### Current State (as of 2026-06-29)

**Status**: Phase 2 Complete, Phase 3 Pending

**✅ Phase 1 Complete** (Repository Setup):
- Repository renamed from `cape-opa-policy` → `cape-opa`
- Development tooling configured (mise.toml, pyproject.toml, requirements-dev.txt)
- AGENTS.md with mandatory context enforcement
- Comprehensive design documentation in notes/
- OPA version: 1.18.0, Python version: 3.11

**✅ Phase 2 Complete** (OPA Policies):
- Main authorization policy with tributary-based access control
- Query policy for listing user-writable resources
- 7 comprehensive tests (all passing)
- Rego v1 syntax for OPA 1.18.0 compatibility
- Policy bundle build script
- Updated CI/CD workflows

**❌ Phase 3 Pending** (Lambda Bundle Generator):
- Lambda function for generating data bundles from PostgreSQL
- Lambda build script
- Lambda deployment package
- Integration with Pulumi deployment

**Repository Structure**:
```
cape-opa/
├── policies/                          # OPA policy source
│   ├── cape/                         # Policy package
│   │   ├── authorize.rego           # Main authorization logic ✅
│   │   └── user_writeable_resources.rego  # Query policy ✅
│   ├── tests/                       # Policy tests
│   │   ├── authorize_test.rego      # Authorization tests ✅
│   │   └── user_writeable_resources_test.rego  # Query tests ✅
│   └── .manifest.template           # Bundle manifest template ✅
├── scripts/                         # Build automation
│   └── build_policy_bundle.sh      # Policy bundle builder ✅
├── bundle-generator/                # Lambda source (NOT YET IMPLEMENTED)
│   ├── lambda_function.py          # Lambda handler ❌
│   ├── requirements.txt            # Dependencies ❌
│   └── tests/                      # Lambda tests ❌
├── .github/workflows/
│   ├── test.yml                    # CI testing ✅
│   └── release.yml                 # Release automation ✅
├── notes/                          # Design documentation ✅
├── mise.toml                       # Tool versions ✅
├── pyproject.toml                  # Python config ✅
└── AGENTS.md                       # This file ✅
```

### Testing

**Test OPA policies:**
```bash
opa test policies/ -v
```

**Build policy bundle:**
```bash
./scripts/build_policy_bundle.sh <version>
# Example: ./scripts/build_policy_bundle.sh 2026.06.29
```

**Run CI tests locally:**
```bash
# Ensure mise tools are available
mise install

# Run OPA tests
opa test policies/ -v

# Build test bundle
opa build -b policies/cape/ -o test-bundle.tar.gz
```

### Release Process

Releases use date-based versioning (YYYY.MM.DD format) and are created via GitHub Actions:

1. Go to Actions → "CAPE OPA Bundle Release"
2. Click "Run workflow"
3. Workflow will:
   - Create date-based tag (e.g., 2026.06.29)
   - Run policy tests
   - Build policy bundle
   - Generate SHA256 checksums
   - Create GitHub release with artifacts

---

## Development Workflow

1. Make changes to policies or code
2. Run tests to verify correctness (`opa test policies/ -v`)
3. Update context in notes/ to reflect changes
4. Commit with descriptive message
5. Push to feature branch
6. Verify context is current before completing work

---

## External Dependencies

- **OPA 1.18.0**: Policy evaluation engine (installed via mise)
- **Python 3.11**: For Lambda development (installed via mise)
- **cape-cod-db 0.3.0**: Database schema library (PyPI package, for Lambda phase)
- **cape-cod**: Pulumi infrastructure (OPA EC2, Lambda resources)
- **cape-cod-env**: Ansible deployment automation (deploys policy bundles to OPA servers)

See notes/06-pulumi-integration.md and notes/07-ansible-integration.md for integration details.

---

## Next Steps (Phase 3)

When resuming work on Phase 3:

1. **Read context**: Review all notes/*.md files, especially:
   - notes/03-bundle-generator.md (complete Lambda code specification)
   - notes/04-build-scripts.md (Lambda build script specification)
   - notes/06-pulumi-integration.md (Lambda deployment details)

2. **Implement Lambda function**:
   - Create bundle-generator/lambda_function.py (~400 lines)
   - Create bundle-generator/requirements.txt (cape-cod-db==0.3.0, boto3)
   - Query PostgreSQL for users, tributaries, resources, user_attributes
   - Generate OPA data bundle JSON
   - Upload to S3 bucket

3. **Add Lambda build script**:
   - Create scripts/build_lambda_package.sh
   - Package Lambda code + dependencies into zip file

4. **Update release workflow**:
   - Add Lambda package build step
   - Include Lambda zip in release artifacts

5. **Test end-to-end**:
   - Local Lambda testing with mocked database
   - Integration testing with Docker Compose (see notes/08-testing.md)

6. **Update context**:
   - Mark Lambda as implemented in notes/03-bundle-generator.md
   - Update this file (AGENTS.md) to reflect Phase 3 completion

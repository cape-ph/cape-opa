# Agent Instructions for cape-opa-policy

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
- Add/modify OPA policies → Update notes/policies.md
- Change Lambda code → Update notes/bundle-generator.md
- Modify build scripts → Update notes/build-deployment.md
- Update integration points → Update notes/integration.md

### Verification Checklist

Before marking work complete:
- [ ] All relevant notes/*.md files reflect changes made
- [ ] Architecture diagrams updated if structure changed
- [ ] Integration points documented if external contracts changed
- [ ] No stale information remains in context

**Work is INCOMPLETE without context updates.**

---

## Project Overview

This repository contains OPA (Open Policy Agent) policies and data bundle generation for CAPE's authorization system.

### Key Components

1. **OPA Policies** (`cape/`): Rego policies for authorization decisions
2. **Bundle Generator Lambda** (planned): Dynamic data bundle generation from PostgreSQL
3. **Build Scripts** (planned): Bundle creation automation
4. **GitHub Actions** (planned): Release automation

### Current State

**Status**: Early development - repository being restructured

The repository currently contains:
- Basic allow-all policy (`cape/capeallow.rego`)
- Design documents in `.design/` describing future architecture

See `.design/cape-opa-README.md` for the complete implementation plan.

### Testing

Test policies with:
```bash
opa test cape/ -v
```

Build bundles with:
```bash
opa build -b cape/ -o bundle.tar.gz
```

---

## Development Workflow

1. Make changes to policies or code
2. Run tests to verify correctness
3. Update context in notes/ to reflect changes
4. Verify context is current before completing work

---

## External Dependencies

- **cape-cod-db**: Database schema (when Lambda is implemented)
- **cape-cod**: Pulumi infrastructure (OPA EC2, Lambda resources)
- **cape-cod-env**: Ansible deployment automation

See notes/integration.md for integration details.

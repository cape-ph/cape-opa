# Project Context Notes

This directory contains comprehensive documentation that agents MUST read at session start and maintain throughout work.

## Purpose

These notes provide complete implementation specifications including:
- Current project state and architecture
- Full code examples for all components (Rego policies, Python Lambda, build scripts, YAML workflows)
- Integration patterns with other CAPE repositories (cape-cod, cape-cod-env, cape-cod-db)
- Deployment workflows and developer procedures
- Open questions and future considerations

## Structure

Files are numbered to indicate logical reading order:

- **00-overview.md** - Project purpose, status, roadmap, dependencies
- **01-architecture.md** - System design, data flows, architectural decisions
- **02-policies.md** - OPA policies with complete Rego code and tests
- **03-bundle-generator.md** - Lambda function with complete Python implementation
- **04-build-scripts.md** - Build automation scripts (bash) with complete code
- **05-github-actions.md** - GitHub Actions workflows with complete YAML
- **06-pulumi-integration.md** - Pulumi infrastructure code (Python)
- **07-ansible-integration.md** - Ansible playbooks with complete YAML
- **08-testing.md** - Testing strategy options with examples
- **09-deployment-workflows.md** - Five complete deployment scenarios
- **10-developer-procedures.md** - Step-by-step developer workflows
- **11-open-questions.md** - Team decisions needed
- **12-future-considerations.md** - Future enhancements and evolution

## Reading Order

**For new agents** starting work on this project:
1. Read 00-overview.md to understand project purpose
2. Read 01-architecture.md to understand system design
3. Read files 02-12 as needed based on work area

**For implementation work**:
- Policies → 02-policies.md
- Lambda → 03-bundle-generator.md
- Build/Release → 04-build-scripts.md, 05-github-actions.md
- Infrastructure → 06-pulumi-integration.md, 07-ansible-integration.md
- Testing → 08-testing.md
- Deployment → 09-deployment-workflows.md

## Maintenance

**CRITICAL**: Update relevant notes in the SAME session as code changes.

When you:
- Add/modify OPA policies → Update 02-policies.md
- Change Lambda code → Update 03-bundle-generator.md
- Modify build scripts → Update 04-build-scripts.md
- Change GitHub Actions → Update 05-github-actions.md
- Update Pulumi integration → Update 06-pulumi-integration.md
- Modify Ansible playbooks → Update 07-ansible-integration.md
- Change testing approach → Update 08-testing.md
- Add deployment scenarios → Update 09-deployment-workflows.md
- Update workflows → Update 10-developer-procedures.md

## Nature of These Files

These are NOT traditional documentation files - they are **operational context** for agents to maintain project understanding across sessions. They contain:
- Complete code examples (ready to copy/paste)
- Architectural rationale (why decisions were made)
- Implementation constraints (critical requirements)
- Integration contracts (how components communicate)

All code in these files reflects the PLANNED architecture from the design phase. Implementation status is tracked in 00-overview.md.

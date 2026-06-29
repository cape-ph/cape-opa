# CAPE OPA Authorization Policies

OPA (Open Policy Agent) policy bundles for CAPE's attribute-based access control (ABAC).

> **Repository Rename Notice**: This repository was renamed from `cape-opa-policy` to `cape-opa`. 
> If you have an existing clone, update your remote: `git remote set-url origin git@github.com:cape-ph/cape-opa.git`

> **Restructuring in Progress**: This repository is undergoing active restructuring to implement 
> the complete CAPE authorization architecture. Directory structure and workflows will see 
> significant changes in the near term.

## Development Setup

### Prerequisites

- [mise](https://mise.jdx.dev/) - Tool version management

### Quick Start

```bash
# Install required tools (python, opa)
mise install

# Install Python development tools
pip install -r requirements-dev.txt

# Verify installations
python --version  # 3.11.x
opa version       # 1.18.0
```

## Current Structure

```
cape-opa/
├── cape/           # Current OPA policies
├── AGENTS.md       # Agent development guidelines
└── notes/          # Architecture documentation (for agents)
```

## Testing

### Test Policies

```bash
opa test cape/ -v
```

### Format Code (when Python code exists)

```bash
black .
isort .
ruff check .
```

## Releases

Releases are created via GitHub Actions workflow.

**To create a release**:
1. Go to GitHub Actions tab
2. Run "CAPE OPA Bundle Release" workflow (manual dispatch)
3. Release tagged with current date: `YYYY.MM.DD[.revision]`

**Release artifacts**:
- `cape-opa-bundle.tar.gz` - OPA policy bundle

## License

Apache-2.0 (see LICENSE file)

# OPA Policies

## Current State

**Implemented**: `cape/capeallow.rego`
- Simple allow-all policy for initial testing
- Used to verify decision logging works

**Not Yet Implemented**: Full authorization policies (complete code below)

## Planned Repository Structure

```
policies/
├── cape/
│   ├── authorize.rego                  # Main authorization logic
│   ├── user_writeable_resources.rego   # Query: writable paths
│   ├── user_readable_resources.rego    # Query: readable paths (future)
│   └── helpers.rego                    # Shared utility functions (future)
├── tests/
│   ├── authorize_test.rego
│   ├── user_writeable_resources_test.rego
│   └── test_data.json
└── .manifest.template                   # Bundle manifest template
```

## Complete Policy Code

### policies/.manifest.template

```json
{
  "revision": "${GIT_COMMIT}",
  "roots": ["cape"],
  "metadata": {
    "version": "${VERSION}",
    "built_at": "${BUILD_TIMESTAMP}",
    "repository": "https://github.com/cape-ph/cape-opa"
  }
}
```

Variables `${GIT_COMMIT}`, `${VERSION}`, `${BUILD_TIMESTAMP}` are substituted by `build_policy_bundle.sh` script.

### policies/cape/authorize.rego

Complete main authorization policy:

```rego
package cape

# Main authorization policy for CAPE resources

# Default deny
default allow = false
default reason = "Access denied"

# RULE: Deny if user is quarantined, suspended, or deactivated
allow = false {
    user_status := get_user_status(input.user.id)
    user_status in ["quarantine", "suspended", "deactivated"]
}

reason = "User account is not active" {
    user_status := get_user_status(input.user.id)
    user_status in ["quarantine", "suspended", "deactivated"]
}

# RULE: Allow write if user in tributary with write access
allow {
    input.action == "write"
    user_writable(input.user.id, input.resource.path)
}

reason = "Write access granted via tributary membership" {
    input.action == "write"
    user_writable(input.user.id, input.resource.path)
}

# RULE: Allow read if user in tributary with read access
allow {
    input.action == "read"
    user_readable(input.user.id, input.resource.path)
}

reason = "Read access granted via tributary membership" {
    input.action == "read"
    user_readable(input.user.id, input.resource.path)
}

# RULE: Admins can access everything
allow {
    is_admin(input.user.id)
}

reason = "Admin access granted" {
    is_admin(input.user.id)
}

# Helper: Check if user can write to path
user_writable(user_id, path) {
    # Get user's tributaries
    membership := data.user_tributaries[_]
    membership.user_id == user_id
    
    # Find resources for those tributaries
    resource := data.resources[_]
    resource.tributary_id == membership.tributary_id
    resource.access_pattern == "write"
    
    # Check if path matches resource
    startswith(path, resource.resource_identifier)
}

# Helper: Check if user can read from path
user_readable(user_id, path) {
    membership := data.user_tributaries[_]
    membership.user_id == user_id
    
    resource := data.resources[_]
    resource.tributary_id == membership.tributary_id
    resource.access_pattern in ["read", "both"]
    
    startswith(path, resource.resource_identifier)
}

# Helper: Check if user is admin
is_admin(user_id) {
    attr := data.user_attributes[_]
    attr.user_id == user_id
    attr.attribute_key == "is_admin"
    attr.attribute_value == "true"
}

# Helper: Get user status
get_user_status(user_id) = status {
    attr := data.user_attributes[_]
    attr.user_id == user_id
    attr.attribute_key == "user_status"
    status := attr.attribute_value
} else = "active" {
    # Default to active if no status attribute
    true
}
```

### policies/cape/user_writeable_resources.rego

Query policy for listing writable resources:

```rego
package cape

# Query: List all S3 paths this user can write to
user_writeable_resources[resource_info] {
    # Get user's tributary memberships
    membership := data.user_tributaries[_]
    membership.user_id == input.user_id
    
    # Get tributary details
    tributary := data.tributaries[_]
    tributary.id == membership.tributary_id
    
    # Get writable resources for this tributary
    resource := data.resources[_]
    resource.tributary_id == tributary.id
    resource.access_pattern == "write"
    
    # Build response object
    resource_info := {
        "resource_identifier": resource.resource_identifier,
        "resource_type": resource.resource_type,
        "tributary_id": tributary.id,
        "tributary_name": tributary.name,
        "metadata": resource.metadata
    }
}
```

## Complete Test Code

### policies/tests/authorize_test.rego

Complete test suite with fixtures:

```rego
package cape

# Test: Active user can write to tributary resource
test_allow_write_to_tributary_resource {
    allow with input as {
        "user": {"id": 1},
        "action": "write",
        "resource": {
            "type": "s3",
            "path": "s3://test-bucket/eng/raw-uploads/file.csv"
        }
    } with data as test_data
}

# Test: User cannot write to resource they don't have access to
test_deny_write_to_unauthorized_resource {
    not allow with input as {
        "user": {"id": 2},
        "action": "write",
        "resource": {
            "type": "s3",
            "path": "s3://test-bucket/eng/raw-uploads/file.csv"
        }
    } with data as test_data
}

# Test: Quarantined user denied all access
test_deny_quarantined_user {
    not allow with input as {
        "user": {"id": 3},
        "action": "write",
        "resource": {
            "type": "s3",
            "path": "s3://test-bucket/ds/raw-uploads/file.csv"
        }
    } with data as test_data
}

# Test data fixture
test_data := {
  "users": [
    {"id": 1, "email": "alice@example.com"},
    {"id": 2, "email": "bob@example.com"},
    {"id": 3, "email": "quarantined@example.com"}
  ],
  "tributaries": [
    {"id": 1, "name": "ENG"},
    {"id": 2, "name": "DS"}
  ],
  "user_tributaries": [
    {"user_id": 1, "tributary_id": 1},
    {"user_id": 1, "tributary_id": 2},
    {"user_id": 2, "tributary_id": 2}
  ],
  "resources": [
    {
      "id": 1,
      "tributary_id": 1,
      "resource_identifier": "s3://test-bucket/eng/raw-uploads/",
      "access_pattern": "write"
    },
    {
      "id": 2,
      "tributary_id": 1,
      "resource_identifier": "s3://test-bucket/eng/clean-uploads/",
      "access_pattern": "read"
    }
  ],
  "user_attributes": [
    {"user_id": 1, "attribute_key": "user_status", "attribute_value": "active"},
    {"user_id": 2, "attribute_key": "user_status", "attribute_value": "active"},
    {"user_id": 3, "attribute_key": "user_status", "attribute_value": "quarantine"}
  ]
}
```

## Policy Behavior

### Input Format

Authorization decisions:
```json
{
  "user": {"id": 123},
  "action": "write",
  "resource": {
    "type": "s3",
    "path": "s3://bucket/tributary/raw-uploads/file.csv"
  }
}
```

Resource queries:
```json
{
  "user_id": 123
}
```

### Output Format

Authorization decision:
```json
{
  "allow": true,
  "reason": "Write access granted via tributary membership"
}
```

Resource query:
```json
{
  "user_writeable_resources": [
    {
      "resource_identifier": "s3://bucket/eng/raw-uploads/",
      "resource_type": "s3",
      "tributary_id": 1,
      "tributary_name": "ENG",
      "metadata": {}
    }
  ]
}
```

## Data Dependencies

Policies require data bundle with these collections:

- **data.users** - User records (id, email)
- **data.tributaries** - Tributary records (id, name, description)
- **data.user_tributaries** - User-tributary memberships (user_id, tributary_id, granted_at)
- **data.resources** - Resource definitions (id, tributary_id, resource_type, resource_identifier, access_pattern, metadata)
- **data.user_attributes** - User attributes (user_id, attribute_key, attribute_value)

Data is generated by Lambda function (see 03-bundle-generator.md).

## Testing

### Local Testing

```bash
# Test policies
cd policies
opa test . -v

# Build bundle
opa build -b cape/ -o bundle.tar.gz

# Inspect bundle
tar -tzf bundle.tar.gz
```

### CI Testing

GitHub Actions runs tests on every commit (see 05-github-actions.md):
```bash
opa test policies/ -v
```

### Integration Testing

See 08-testing.md for full integration testing with Docker Compose.

## Policy Development Workflow

1. **Edit policy**: Modify `policies/cape/*.rego`
2. **Update tests**: Add/modify `policies/tests/*_test.rego`
3. **Run tests**: `opa test policies/ -v`
4. **Build bundle**: `opa build -b policies/cape/ -o test-bundle.tar.gz`
5. **Verify**: `tar -tzf test-bundle.tar.gz`
6. **Update notes**: Update this file (02-policies.md)
7. **Commit and push**
8. **Create release** (see 04-build-scripts.md, 05-github-actions.md)

## Bundle Structure

Policy bundles contain policies only (no data):

```
policy-bundle-v1.2.3.tar.gz
├── .manifest
└── cape/
    ├── authorize.rego
    ├── user_writeable_resources.rego
    └── (other .rego files)
```

Manifest includes:
- revision (git commit hash)
- version (git tag)
- build timestamp
- repository URL

Data bundles are separate (generated by Lambda, see 03-bundle-generator.md).

## Authorization Rules Summary

1. **Default deny**: All access denied unless explicitly allowed
2. **User status check**: Quarantined/suspended/deactivated users always denied
3. **Tributary-based access**: Users access resources via tributary memberships
4. **Path matching**: Resource access uses prefix matching (`startswith`)
5. **Access patterns**: read, write, both
6. **Admin override**: Admin users (is_admin=true) can access everything
7. **Reason tracking**: Every decision includes a human-readable reason

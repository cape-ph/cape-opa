# Future Considerations

## Enhancements to Consider

These are potential improvements and features to consider as the project matures. Not prioritized or scheduled.

---

## 1. Automated Dependency Updates

**Problem**: When cape-cod-db releases new version, cape-opa needs manual update

**Current Process**:
```bash
# Manual steps
cd cape-opa/bundle-generator
vim requirements.txt  # Update version
vim lambda_function.py  # Update code
git commit && git tag && git push
```

**Potential Solution**: Dependabot or Renovate Bot

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "pip"
    directory: "/bundle-generator"
    schedule:
      interval: "weekly"
    reviewers:
      - "cape-team"
    labels:
      - "dependencies"
```

**Benefits**:
- Auto-creates PRs when cape-cod-db updates
- Keeps dependencies current
- Reduces manual work

**Considerations**:
- May require code changes (not just version bump)
- Need good test coverage
- CI must catch incompatibilities

**Status**: Future enhancement when team bandwidth allows

---

## 2. Seed Data Management

**Known Limitation**: No versioned data in bundles yet (all dynamic)

**Future Need**: May need to version-control some data for:
- Auditing requirements (who had access when?)
- Regulatory compliance (reproducible history)
- Reproducible testing (consistent test data)
- Historical analysis (policy decisions over time)
- Demo environments (known-good data)

**Potential Approach**:

```
cape-opa/
├── policies/
├── bundle-generator/
└── seed/  (NEW)
    ├── users_baseline.json
    ├── tributaries_initial.json
    └── resources_demo.json
```

**Bundle Generator Logic**:
```python
def generate_bundle_data(db_url):
    # Load seed data from repo
    seed_data = load_seed_data()
    
    # Query dynamic data from database
    db_data = query_authorization_data(db_url)
    
    # Merge (database overrides seed)
    merged_data = merge_data(seed_data, db_data)
    
    return merged_data
```

**Use Cases**:
- **Demo environment**: Seed with realistic but fake data
- **Testing**: Reproducible test scenarios
- **Auditing**: Baseline data for compliance
- **Disaster recovery**: Restore authorization quickly

**Triggers**:
- Customer audit requirements
- Compliance mandates (SOC2, HIPAA, etc.)
- Team decision to version specific data

**Status**: Monitor customer needs, implement when required

---

## 3. OPA Config Migration

**Current State**: OPA config in cape-cod Pulumi (user-data script)

**Future State**: Config template in cape-opa (better co-location)

**Migration Path**:

1. **Create config template** in cape-opa:
```yaml
# config/opa-config.yaml.j2
services:
  s3:
    url: https://s3.amazonaws.com/{{ meta_assets_bucket }}
    credentials:
      s3_signing:
        environment_credentials: {}

bundles:
  policies:
    service: s3
    resource: opa/policies/policy-bundle-latest.tar.gz
    polling:
      min_delay_seconds: 10
      max_delay_seconds: 30
  
  data:
    service: s3
    resource: opa/data/data-bundle-latest.tar.gz
    polling:
      min_delay_seconds: 10
      max_delay_seconds: 30
```

2. **Include in release artifacts**
3. **Ansible downloads and renders** template
4. **Ansible deploys** to OPA EC2
5. **Remove from Pulumi** user-data

**Benefits**:
- All OPA concerns in one repo
- Config changes don't require Pulumi changes
- Easier to test config changes
- Config versioned with policies

**Considerations**:
- Ansible becomes responsible for config
- More complex initial setup
- Config separated from infrastructure definition

**Status**: Defer until OPA config needs frequent changes

---

## 4. Admin UI for Policy Management

**Vision**: Web UI for non-developers to manage some aspects

**Examples**:

### User Management UI
- Add user to tributary (database change, not policy)
- View user's current access
- Audit user access history

### Policy Viewer UI
- View current authorization rules (read-only)
- Test authorization scenarios
- Visualize policy logic

### Bundle Inspector UI
- View current policy bundle version
- View current data bundle timestamp
- View data bundle contents (for debugging)

**Architecture**:
```
┌─────────────┐
│   Web UI    │
│  (React)    │
└──────┬──────┘
       │
       ▼
┌─────────────┐      ┌──────────┐
│  API Lambda │ ───► │ Database │
│             │      │ (read)   │
└──────┬──────┘      └──────────┘
       │
       ▼
┌─────────────┐
│     OPA     │
│  (query)    │
└─────────────┘
```

**Complexity**: High - requires:
- UI development
- API for safe operations
- Policy representation that UI can manipulate
- Validation and testing
- RBAC for UI itself

**Status**: Far future, requires significant investment

---

## 5. Multi-Environment Promotion Workflow

**Current**: Manual deployment to each environment

**Future**: Automated promotion workflow

**Workflow**:

```
1. Developer pushes to main
   ↓
2. CI tests pass
   ↓
3. Auto-deploy to dev
   ↓
4. Run integration tests
   ↓
5. Create release candidate (v1.2.3-rc1)
   ↓
6. Auto-deploy to staging
   ↓
7. Run smoke tests
   ↓
8. Manual approval required
   ↓
9. Promote to prod (tag v1.2.3)
   ↓
10. Auto-deploy to prod
```

**Benefits**:
- Faster deployments
- Consistent process
- Reduced manual errors
- Audit trail

**Implementation**:
- GitHub Actions workflow
- Pulumi automation API
- Ansible automation
- Slack approval bot

**Status**: Address when team needs multiple environments and has mature CI/CD

---

## 6. Policy Performance Optimization

**Current**: Standard OPA evaluation

**Future Optimizations**:

### Partial Evaluation
Pre-compute policy decisions for known scenarios:
```bash
opa build -b policies/ --optimize 1 -o optimized-bundle.tar.gz
```

### Caching
Cache authorization decisions (with short TTL):
```python
# In application code
@cache(ttl=60)
def check_authorization(user_id, action, resource):
    return opa_client.authorize(user_id, action, resource)
```

### Indexing
Add indexes to data bundle for faster lookups:
```json
{
  "users": [...],
  "user_index": {
    "1": {"tributaries": [1, 2]},
    "2": {"tributaries": [2]}
  }
}
```

**When Needed**: If authorization checks become a bottleneck

**Status**: Optimize only when measurements show need

---

## 7. Advanced Monitoring and Observability

**Current**: Basic CloudWatch logs

**Future**:

### Distributed Tracing
Use AWS X-Ray to trace:
- Lambda invocation
- Database queries
- S3 uploads
- OPA decision evaluation

### Custom Metrics Dashboard
CloudWatch dashboard showing:
- Bundle generation trends
- Policy evaluation latency
- Deny rate by resource type
- User access patterns

### Anomaly Detection
CloudWatch Anomaly Detection for:
- Sudden spike in denials
- Unusual bundle sizes
- Unexpected Lambda errors

### Correlation with Application Metrics
Link OPA metrics to application behavior:
- Slow API responses ← OPA latency
- User complaints ← Authorization denials
- Deployment issues ← Bundle updates

**Status**: Expand monitoring based on operational experience

---

## 8. Policy as Code Best Practices

**Future Improvements**:

### Policy Modules
Split large policies into modules:
```
policies/cape/
├── authorization/
│   ├── s3.rego      # S3-specific rules
│   ├── ec2.rego     # EC2-specific rules
│   └── iam.rego     # IAM-specific rules
├── helpers/
│   ├── path.rego    # Path matching utilities
│   └── user.rego    # User attribute utilities
└── main.rego        # Entry point
```

### Policy Linting
Custom OPA linting rules:
```rego
# policies/lint/enforce_reason.rego
deny[msg] {
    # Every allow rule must have a corresponding reason rule
    some rule_name
    data.cape[rule_name].allow
    not data.cape[rule_name].reason
    msg := sprintf("Rule %s missing reason", [rule_name])
}
```

### Policy Documentation Generator
Auto-generate docs from policy annotations:
```rego
# METADATA
# title: S3 Write Authorization
# description: Allows users to write to S3 buckets they have tributary access to
# authors:
#   - name: CAPE Team
allow {
    input.action == "write"
    user_writable(input.user.id, input.resource.path)
}
```

**Status**: Implement as complexity grows

---

## 9. Blue/Green Lambda Deployments

**Current**: Direct Lambda update (brief downtime possible)

**Future**: Blue/green deployment

**Process**:
1. Deploy new Lambda version as separate function
2. Run integration tests against new version
3. Switch EventBridge to new Lambda (atomic cutover)
4. Monitor error rates
5. Keep old Lambda for quick rollback
6. Delete old Lambda after verification period (e.g., 24 hours)

**Benefits**:
- Zero-downtime deployments
- Easy rollback
- Test in production environment

**Implementation**:
```python
# In Pulumi
lambda_blue = aws.lambda_.Function("opa-bundle-generator-blue", ...)
lambda_green = aws.lambda_.Function("opa-bundle-generator-green", ...)

# Switch target
active_lambda = lambda_green if config.get("active") == "green" else lambda_blue

aws.cloudwatch.EventTarget(
    "schedule-target",
    rule=schedule_rule.name,
    arn=active_lambda.arn
)
```

**Status**: Implement when Lambda stability is critical

---

## 10. Compliance and Auditing Features

**Future Requirements** (if needed for compliance):

### Audit Logging
Log every authorization decision:
```json
{
  "timestamp": "2026-06-29T12:00:00Z",
  "user_id": 123,
  "action": "write",
  "resource": "s3://bucket/eng/file.csv",
  "decision": "allow",
  "reason": "Write access granted via tributary membership",
  "policy_version": "v1.2.3",
  "data_bundle_revision": "abc123"
}
```

### Immutable Policy History
Store policy bundles permanently:
```
s3://cape-compliance/opa/policies/
├── v1.0.0/
├── v1.1.0/
└── v1.2.3/
    ├── policy-bundle.tar.gz
    ├── checksum.txt
    └── metadata.json
```

### Access Reports
Generate reports for auditors:
- Who has access to what resources?
- When did user X gain access to resource Y?
- What policy version was active on date Z?

**Status**: Implement when compliance requirements are known

---

## Summary

These considerations are **not prioritized or scheduled**. They represent potential future directions based on:
- Anticipated needs
- Industry best practices
- Operational experience
- Team capacity

**Review Periodically**: Revisit this list quarterly to assess relevance and priority.

**Add New Ideas**: As the project evolves, add new considerations here.

**Graduate to Backlog**: When a consideration becomes a clear need, move it to the project backlog for planning.

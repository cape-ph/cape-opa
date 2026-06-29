# Ansible Integration

## Overview

Ansible (in cape-cod-env repository) handles:
- Downloading policy bundles from cape-opa GitHub releases
- Uploading policy bundles to S3
- Running database migrations (cape-cod-db)
- Optionally triggering Lambda for initial data bundle

**Location**: `cape-cod-env` repository (Ansible playbooks)

## Group Variables

### File: cape-cod-env/group_vars/all.yml

Configuration for all environments:

```yaml
# OPA Configuration
opa_version: "v1.2.3"
opa_release_base_url: "https://github.com/cape-ph/cape-opa/releases/download/{{ opa_version }}"

# S3 Configuration
meta_assets_bucket: "cape-meta-assets-{{ env }}"
opa_s3_prefix: "opa/"

# Artifacts
opa_artifacts:
  policy_bundle: "policy-bundle-{{ opa_version }}.tar.gz"
  checksums: "checksums.txt"

# Download directory
opa_download_dir: "/tmp/opa-artifacts"
```

### File: cape-cod-env/group_vars/dev.yml

Dev environment overrides:

```yaml
env: "dev"
meta_assets_bucket: "cape-meta-assets-dev"
```

### File: cape-cod-env/group_vars/prod.yml

Prod environment overrides:

```yaml
env: "prod"
meta_assets_bucket: "cape-meta-assets-prod"

# More stringent verification in prod
opa_verify_checksums: true
```

## Complete Playbooks

### File: cape-cod-env/playbooks/deploy_opa_bundles.yml

Complete playbook for deploying OPA policy bundles:

```yaml
---
- name: Deploy OPA Policy Bundles to S3
  hosts: localhost
  gather_facts: false
  
  vars:
    download_dir: "{{ opa_download_dir | default('/tmp/opa-artifacts') }}"
  
  tasks:
    - name: Create download directory
      file:
        path: "{{ download_dir }}"
        state: directory
        mode: '0755'
    
    - name: Download policy bundle from GitHub release
      get_url:
        url: "{{ opa_release_base_url }}/{{ opa_artifacts.policy_bundle }}"
        dest: "{{ download_dir }}/{{ opa_artifacts.policy_bundle }}"
        mode: '0644'
        timeout: 60
      register: policy_bundle_download
    
    - name: Download checksums
      get_url:
        url: "{{ opa_release_base_url }}/{{ opa_artifacts.checksums }}"
        dest: "{{ download_dir }}/{{ opa_artifacts.checksums }}"
        mode: '0644'
        timeout: 30
      register: checksums_download
    
    - name: Verify checksum
      shell: |
        cd {{ download_dir }}
        grep {{ opa_artifacts.policy_bundle }} {{ opa_artifacts.checksums }} | sha256sum -c -
      register: checksum_verify
      failed_when: checksum_verify.rc != 0
      changed_when: false
    
    - name: Display checksum verification result
      debug:
        msg: "✓ Checksum verified: {{ opa_artifacts.policy_bundle }}"
    
    - name: Upload policy bundle to S3 (versioned)
      aws_s3:
        bucket: "{{ meta_assets_bucket }}"
        object: "{{ opa_s3_prefix }}policies/{{ opa_artifacts.policy_bundle }}"
        src: "{{ download_dir }}/{{ opa_artifacts.policy_bundle }}"
        mode: put
        overwrite: always
        permission: private
      register: s3_upload_versioned
    
    - name: Upload policy bundle as latest (for OPA to poll)
      aws_s3:
        bucket: "{{ meta_assets_bucket }}"
        object: "{{ opa_s3_prefix }}policies/policy-bundle-latest.tar.gz"
        src: "{{ download_dir }}/{{ opa_artifacts.policy_bundle }}"
        mode: put
        overwrite: always
        permission: private
      register: s3_upload_latest
    
    - name: Set S3 object metadata
      command: >
        aws s3api copy-object
        --bucket {{ meta_assets_bucket }}
        --copy-source {{ meta_assets_bucket }}/{{ opa_s3_prefix }}policies/{{ opa_artifacts.policy_bundle }}
        --key {{ opa_s3_prefix }}policies/{{ opa_artifacts.policy_bundle }}
        --metadata version={{ opa_version }},deployed_at={{ ansible_date_time.iso8601 }}
        --metadata-directive REPLACE
      changed_when: false
    
    - name: Cleanup download directory
      file:
        path: "{{ download_dir }}"
        state: absent
      when: cleanup_downloads | default(true)
    
    - name: Log deployment
      debug:
        msg: |
          ✓ Deployed OPA policy bundle {{ opa_version }} to S3
          - Versioned: s3://{{ meta_assets_bucket }}/{{ opa_s3_prefix }}policies/{{ opa_artifacts.policy_bundle }}
          - Latest:    s3://{{ meta_assets_bucket }}/{{ opa_s3_prefix }}policies/policy-bundle-latest.tar.gz
```

### File: cape-cod-env/playbooks/trigger_opa_bundle_generation.yml

Playbook to manually trigger Lambda for initial data bundle:

```yaml
---
- name: Trigger OPA Data Bundle Generation
  hosts: localhost
  gather_facts: false
  
  vars:
    pulumi_stack_dir: "{{ lookup('env', 'PULUMI_STACK_DIR') | default('../cape-cod') }}"
  
  tasks:
    - name: Get Lambda function name from Pulumi outputs
      shell: |
        cd {{ pulumi_stack_dir }}
        pulumi stack output opa_bundle_lambda_name
      register: lambda_name_result
      changed_when: false
    
    - name: Set Lambda function name fact
      set_fact:
        lambda_function_name: "{{ lambda_name_result.stdout | trim }}"
    
    - name: Display Lambda function name
      debug:
        msg: "Lambda function: {{ lambda_function_name }}"
    
    - name: Invoke Lambda function
      command: >
        aws lambda invoke
        --function-name {{ lambda_function_name }}
        --invocation-type RequestResponse
        --payload '{}'
        --cli-binary-format raw-in-base64-out
        /tmp/lambda-response.json
      register: lambda_invoke_result
      changed_when: false
    
    - name: Read Lambda response
      slurp:
        src: /tmp/lambda-response.json
      register: lambda_response_content
    
    - name: Parse Lambda response
      set_fact:
        lambda_response: "{{ lambda_response_content.content | b64decode | from_json }}"
    
    - name: Display Lambda response
      debug:
        msg: "{{ lambda_response }}"
    
    - name: Check if bundle generation succeeded
      assert:
        that:
          - lambda_response.statusCode == 200
          - lambda_response.body is defined
        fail_msg: "Lambda invocation failed: {{ lambda_response }}"
        success_msg: "✓ OPA data bundle generated successfully"
    
    - name: Parse response body
      set_fact:
        response_body: "{{ lambda_response.body | from_json }}"
    
    - name: Display generation details
      debug:
        msg: |
          Status: {{ response_body.status }}
          {% if response_body.status == 'success' %}
          Bundle size: {{ response_body.bundle_size }} bytes
          Timestamp: {{ response_body.timestamp }}
          Revision: {{ response_body.revision }}
          Data counts:
            Users: {{ response_body.data_counts.users }}
            Tributaries: {{ response_body.data_counts.tributaries }}
            Resources: {{ response_body.data_counts.resources }}
            User attributes: {{ response_body.data_counts.user_attributes }}
          {% elif response_body.status == 'skipped' %}
          Reason: {{ response_body.reason }}
          Message: {{ response_body.message }}
          {% endif %}
    
    - name: Cleanup response file
      file:
        path: /tmp/lambda-response.json
        state: absent
```

### File: cape-cod-env/playbooks/run_migrations.yml

Playbook for running database migrations:

```yaml
---
- name: Run Database Migrations
  hosts: localhost
  gather_facts: false
  
  vars:
    migrations_venv: "/opt/cape/migrations-venv"
    cape_cod_db_version: "{{ cape_cod_db_version | default('latest') }}"
  
  tasks:
    - name: Create virtualenv for migrations
      pip:
        name:
          - alembic
          - "cape-cod-db=={{ cape_cod_db_version }}"
        virtualenv: "{{ migrations_venv }}"
        virtualenv_command: python3 -m venv
    
    - name: Get database connection info from Secrets Manager
      command: >
        aws secretsmanager get-secret-value
        --secret-id {{ db_secret_id }}
        --query SecretString
        --output text
      register: db_secret_result
      changed_when: false
      no_log: true
    
    - name: Parse database secret
      set_fact:
        db_secret: "{{ db_secret_result.stdout | from_json }}"
      no_log: true
    
    - name: Build database URL
      set_fact:
        database_url: "postgresql://{{ db_secret.username }}:{{ db_secret.password }}@{{ db_secret.host }}:{{ db_secret.port | default(5432) }}/{{ db_secret.dbname }}"
      no_log: true
    
    - name: Run migrations
      shell: |
        source {{ migrations_venv }}/bin/activate
        alembic upgrade head
      environment:
        DATABASE_URL: "{{ database_url }}"
      register: migrations_result
    
    - name: Display migration results
      debug:
        msg: "{{ migrations_result.stdout_lines }}"
```

## Usage Examples

### Deploy Policy Bundle

```bash
cd cape-cod-env

# Deploy to dev
ansible-playbook -i inventory/dev playbooks/deploy_opa_bundles.yml

# Deploy to prod
ansible-playbook -i inventory/prod playbooks/deploy_opa_bundles.yml

# Deploy specific version (override variable)
ansible-playbook -i inventory/dev \
  -e "opa_version=v1.2.4" \
  playbooks/deploy_opa_bundles.yml
```

### Trigger Lambda Manually

```bash
cd cape-cod-env

# Trigger in dev
ansible-playbook -i inventory/dev playbooks/trigger_opa_bundle_generation.yml

# Trigger in prod
ansible-playbook -i inventory/prod playbooks/trigger_opa_bundle_generation.yml
```

### Run Database Migrations

```bash
cd cape-cod-env

# Run migrations in dev
ansible-playbook -i inventory/dev playbooks/run_migrations.yml

# Run migrations in prod
ansible-playbook -i inventory/prod playbooks/run_migrations.yml
```

### Combined Deployment

```bash
cd cape-cod-env

# Full deployment: migrations + policies + trigger Lambda
ansible-playbook -i inventory/dev \
  playbooks/run_migrations.yml \
  playbooks/deploy_opa_bundles.yml \
  playbooks/trigger_opa_bundle_generation.yml
```

## Inventory Structure

### File: cape-cod-env/inventory/dev/hosts

```ini
[localhost]
127.0.0.1 ansible_connection=local

[dev:children]
localhost

[dev:vars]
env=dev
```

### File: cape-cod-env/inventory/prod/hosts

```ini
[localhost]
127.0.0.1 ansible_connection=local

[prod:children]
localhost

[prod:vars]
env=prod
```

## AWS Credentials

Ansible requires AWS credentials to:
- Download from S3 (if private buckets)
- Upload to S3
- Invoke Lambda
- Access Secrets Manager

### Methods

**Option 1**: AWS CLI profile
```bash
export AWS_PROFILE=cape-dev
ansible-playbook ...
```

**Option 2**: Environment variables
```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-east-1
ansible-playbook ...
```

**Option 3**: IAM instance role (if running on EC2)
```yaml
# No explicit credentials needed
# Ansible uses instance metadata
```

## Error Handling

### GitHub Release Not Found

If `get_url` fails with 404:

```
TASK [Download policy bundle from GitHub release] ****
fatal: [localhost]: FAILED! => {"msg": "HTTP Error 404: Not Found"}
```

**Causes**:
- Release doesn't exist (check `opa_version` in group_vars)
- Release not published yet
- Artifact name mismatch

**Solutions**:
- Verify release exists: `gh release view v1.2.3 -R cape-ph/cape-opa`
- Check artifact name matches `opa_artifacts.policy_bundle`
- Ensure GitHub Actions workflow completed successfully

### Checksum Verification Failed

If `sha256sum -c` fails:

```
TASK [Verify checksum] ****
fatal: [localhost]: FAILED! => {"rc": 1, "stderr": "checksum mismatch"}
```

**Causes**:
- Downloaded file corrupted
- Checksums.txt from different release
- File modified after release

**Solutions**:
- Re-download bundle
- Verify checksums.txt matches release version
- Check GitHub release artifacts

### S3 Upload Failed

If `aws_s3` module fails:

```
TASK [Upload policy bundle to S3] ****
fatal: [localhost]: FAILED! => {"msg": "Access Denied"}
```

**Causes**:
- Insufficient IAM permissions
- Bucket doesn't exist
- Bucket in different region

**Solutions**:
- Verify IAM permissions include `s3:PutObject`
- Check bucket name: `aws s3 ls s3://cape-meta-assets-dev`
- Verify AWS credentials

### Lambda Invocation Failed

If Lambda invoke fails:

```
TASK [Invoke Lambda function] ****
fatal: [localhost]: FAILED! => {"rc": 254, "stderr": "Function not found"}
```

**Causes**:
- Lambda not deployed by Pulumi yet
- Wrong AWS region
- Insufficient IAM permissions

**Solutions**:
- Deploy Lambda: `pulumi up` in cape-cod
- Set AWS_REGION environment variable
- Verify IAM permissions include `lambda:InvokeFunction`

## Integration with Pulumi

### Getting Pulumi Outputs

Ansible can retrieve Pulumi stack outputs:

```yaml
- name: Get OPA Lambda name
  shell: |
    cd {{ pulumi_stack_dir }}
    pulumi stack output opa_bundle_lambda_name
  register: lambda_name
```

Or use Pulumi automation API:

```yaml
- name: Get Pulumi outputs as JSON
  shell: |
    cd {{ pulumi_stack_dir }}
    pulumi stack output --json
  register: pulumi_outputs_json

- name: Parse Pulumi outputs
  set_fact:
    pulumi_outputs: "{{ pulumi_outputs_json.stdout | from_json }}"

- name: Use outputs
  debug:
    msg: "Lambda ARN: {{ pulumi_outputs.opa_bundle_lambda_arn }}"
```

## Ansible Vault for Secrets

For sensitive variables (if not using AWS Secrets Manager):

```bash
# Encrypt variable file
ansible-vault encrypt group_vars/prod/vault.yml

# Run playbook with vault password
ansible-playbook playbooks/deploy_opa_bundles.yml --ask-vault-pass
```

### File: group_vars/prod/vault.yml (encrypted)

```yaml
db_password: "supersecret"
github_token: "ghp_..."
```

## Dry Run / Check Mode

Test playbook without making changes:

```bash
ansible-playbook playbooks/deploy_opa_bundles.yml --check

# With diff output
ansible-playbook playbooks/deploy_opa_bundles.yml --check --diff
```

## Logging and Debugging

### Verbose Output

```bash
ansible-playbook playbooks/deploy_opa_bundles.yml -v    # verbose
ansible-playbook playbooks/deploy_opa_bundles.yml -vv   # more verbose
ansible-playbook playbooks/deploy_opa_bundles.yml -vvv  # debug
```

### Save Playbook Output

```bash
ansible-playbook playbooks/deploy_opa_bundles.yml | tee deployment.log
```

### Step-by-Step Execution

```bash
ansible-playbook playbooks/deploy_opa_bundles.yml --step
```

## Future Enhancements

1. **Rollback playbook**: Revert to previous OPA version
2. **Health checks**: Verify OPA loaded new bundles
3. **Notifications**: Slack/email on deployment
4. **Approval gates**: Require confirmation for prod
5. **Parallel deployments**: Deploy to multiple environments
6. **Integration tests**: Run tests after deployment
7. **Ansible Tower/AWX**: Centralized execution and scheduling

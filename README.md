# AAP + HashiCorp Vault OIDC SSH Certificate Demo

End-to-end demo of Ansible Automation Platform 2.7 integrating with HashiCorp Vault using the new OIDC workload identity feature for SSH certificate authentication.

## What This Demo Does

1. **Deploys Vault** on OpenShift in dev mode via Helm
2. **Enables OIDC workload identity** on AAP 2.7 (feature flag)
3. **Configures Vault** as an SSH Certificate Authority with JWT auth pointing to AAP's OIDC provider
4. **Provisions an AWS EC2 host** (RHEL 9) configured to trust Vault's CA
5. **Configures AAP** with a Vault OIDC credential, Machine credential (linked via credential input source), and job templates
6. **Demonstrates** zero-trust SSH access: AAP issues a per-job JWT, Vault signs a short-lived SSH certificate (5min TTL), and the job connects to the EC2 host

## Prerequisites

- `oc` CLI logged into an OpenShift cluster with cluster-admin
- `ansible-playbook` with collections: `ansible.controller`, `kubernetes.core`, `amazon.aws`, `community.hashi_vault`, `community.crypto`
- `helm` CLI with the `openshift-helm-charts` repo
- Python packages: `boto3`, `kubernetes`
- A `.env` file with credentials (see below)

## .env Format

```yaml
aws_access_key_id: AKIA...
aws_secret_access_key: ...
aap_username: admin
aap_hostname: https://aap.example.com
aap_password: ...
```

## Quick Start

```bash
# Run the full setup
bash setup.sh

# Or run phases individually
ansible-playbook playbooks/deploy-vault.yml
ansible-playbook playbooks/enable-oidc.yml
ansible-playbook playbooks/configure-vault.yml
ansible-playbook playbooks/provision-aws-host.yml
ansible-playbook playbooks/configure-aap.yml
```

After setup, launch the **"Demo - Vault SSH Certificate"** job template from the AAP UI.

## Cleanup

```bash
ansible-playbook teardown.yml
```

## Architecture

```
AAP 2.7 (OCP)                    Vault (OCP)                   AWS EC2 (RHEL 9)
     |                                |                              |
     |--- 1. Issue JWT (per-job) ---->|                              |
     |                                |                              |
     |<-- 2. Signed SSH cert (5m) ----|                              |
     |                                                               |
     |--- 3. SSH with signed cert ---------------------------------->|
     |                                                               |
     |                           TrustedUserCAKeys = Vault CA        |
```

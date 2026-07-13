#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

INVENTORY="inventory/localhost.yml"

echo "============================================="
echo "  AAP + Vault OIDC SSH Certificate Demo Setup"
echo "============================================="
echo ""

echo "--- Phase 1: Deploy Vault on OpenShift ---"
ansible-playbook -i "$INVENTORY" playbooks/deploy-vault.yml
echo ""

echo "--- Phase 2: Enable OIDC on AAP 2.7 ---"
ansible-playbook -i "$INVENTORY" playbooks/enable-oidc.yml
echo ""

echo "--- Phase 3: Configure Vault (SSH CA + JWT Auth) ---"
ansible-playbook -i "$INVENTORY" playbooks/configure-vault.yml
echo ""

echo "--- Phase 4: Provision AWS EC2 Host ---"
ansible-playbook -i "$INVENTORY" playbooks/provision-aws-host.yml
echo ""

echo "--- Phase 5: Configure AAP (Credentials + Job Templates) ---"
ansible-playbook -i "$INVENTORY" playbooks/configure-aap.yml
echo ""

echo "============================================="
echo "  Setup Complete!"
echo ""
echo "  Launch the demo job template from AAP:"
echo "  '$(grep aap_demo_template_name group_vars/all.yml | cut -d'"' -f2)'"
echo "============================================="

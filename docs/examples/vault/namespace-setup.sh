#!/bin/bash
# Create the Vault namespace hierarchy for a new business unit.
#
# This script creates:
#   - The BU namespace
#   - SSH CA secrets engine with automation and interactive roles
#   - KV v2 secrets engine
#   - Team child namespaces (optional)
#
# In production, use Terraform instead of this script.

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:?Set VAULT_ADDR}"
BU_NAME="${1:?Usage: $0 <bu-name> [team1 team2 ...]}"
shift
TEAMS=("$@")

echo "=== Creating namespace: ${BU_NAME} ==="
vault namespace create "${BU_NAME}"

echo "=== Enabling SSH CA in ${BU_NAME} ==="
vault secrets enable -namespace="${BU_NAME}" -path=ssh-ca ssh
vault write -namespace="${BU_NAME}" ssh-ca/config/ca generate_signing_key=true

echo "=== Creating SSH roles in ${BU_NAME} ==="
vault write -namespace="${BU_NAME}" ssh-ca/roles/automation \
  key_type=ca \
  algorithm_signer=rsa-sha2-256 \
  allow_user_certificates=true \
  allowed_users="*" \
  default_user=deploy \
  default_extensions='{"permit-pty":""}' \
  ttl=5m \
  max_ttl=30m

vault write -namespace="${BU_NAME}" ssh-ca/roles/interactive \
  key_type=ca \
  algorithm_signer=rsa-sha2-256 \
  allow_user_certificates=true \
  allowed_users="*" \
  default_user=admin \
  default_extensions='{"permit-pty":"","permit-port-forwarding":""}' \
  ttl=30m \
  max_ttl=4h

echo "=== Enabling KV v2 in ${BU_NAME} ==="
vault secrets enable -namespace="${BU_NAME}" -path=kv -version=2 kv

echo "=== Retrieving SSH CA public key ==="
vault read -namespace="${BU_NAME}" -field=public_key ssh-ca/config/ca \
  > "${BU_NAME}-ssh-ca.pub"
echo "CA public key saved to ${BU_NAME}-ssh-ca.pub"
echo "Distribute this to all ${BU_NAME} hosts as /etc/ssh/vault-${BU_NAME}-ca.pub"

for TEAM in "${TEAMS[@]}"; do
  echo "=== Creating child namespace: ${BU_NAME}/${TEAM} ==="
  vault namespace create -namespace="${BU_NAME}" "${TEAM}"
done

echo ""
echo "Namespace ${BU_NAME} is ready."
echo "Next steps:"
echo "  1. Add '${BU_NAME}' to the JWT role bound_claims list"
echo "  2. Create Entra ID groups: AAP-${BU_NAME}-*, Vault-${BU_NAME}-*"
echo "  3. Create AAP org: ${BU_NAME}"
echo "  4. Distribute ${BU_NAME}-ssh-ca.pub to hosts"

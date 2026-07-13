#!/bin/bash
# Configure the AAP OIDC JWT auth and workload policy in Vault.
#
# This is the central configuration that enables AAP's per-job JWTs
# to authenticate to Vault and access BU-scoped secrets and SSH CAs.
#
# Run this once in the root namespace after setting up BU namespaces.

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:?Set VAULT_ADDR}"
AAP_URL="${AAP_URL:?Set AAP_URL e.g. https://aap.example.com}"

echo "=== Enabling JWT auth for AAP OIDC ==="
vault auth enable jwt

vault write auth/jwt/config \
  oidc_discovery_url="${AAP_URL}/o"

echo "=== Getting JWT accessor ==="
JWT_ACCESSOR=$(vault auth list -format=json | jq -r '."jwt/".accessor')
echo "JWT accessor: ${JWT_ACCESSOR}"

echo "=== Creating templated workload policy ==="
# Substitute the accessor into the policy template
sed "s/AUTH_JWT_ACCESSOR/${JWT_ACCESSOR}/g" \
  aap-workload-policy.hcl | vault policy write aap-workload-policy -

echo "=== Creating JWT role for AAP ==="
vault write auth/jwt/role/aap-workload-role \
  @jwt-role-aap.json

echo ""
echo "AAP OIDC workload identity configured."
echo "AAP jobs will authenticate via JWT and receive scoped access"
echo "based on their organization and job template name."
echo ""
echo "To onboard a new BU, add its name to the bound_claims list:"
echo "  vault read auth/jwt/role/aap-workload-role"
echo "  vault write auth/jwt/role/aap-workload-role bound_claims=..."

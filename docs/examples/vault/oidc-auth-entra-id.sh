#!/bin/bash
# Configure Vault OIDC auth method for Microsoft Entra ID (Azure AD).
#
# Requires an Entra ID app registration with:
#   - Redirect URIs for CLI and UI callbacks
#   - Groups claim enabled under Token Configuration
#   - API permission: Group.Read.All (for groups overage handling)

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:?Set VAULT_ADDR}"
TENANT_ID="${AZURE_TENANT_ID:?Set AZURE_TENANT_ID}"
CLIENT_ID="${AZURE_CLIENT_ID:?Set AZURE_CLIENT_ID}"
CLIENT_SECRET="${AZURE_CLIENT_SECRET:?Set AZURE_CLIENT_SECRET}"
VAULT_FQDN="${VAULT_FQDN:?Set VAULT_FQDN e.g. vault.example.com}"

vault auth enable oidc

vault write auth/oidc/config \
  oidc_client_id="${CLIENT_ID}" \
  oidc_client_secret="${CLIENT_SECRET}" \
  default_role="default" \
  oidc_discovery_url="https://login.microsoftonline.com/${TENANT_ID}/v2.0" \
  provider_config='{"provider":"azure"}'

# The "azure" provider automatically handles the groups overage
# problem. When a user belongs to 200+ groups, Azure omits the
# groups claim and sends _claim_names/_claim_sources instead.
# Vault detects this and calls the MS Graph API for the full list.

vault write auth/oidc/role/default \
  user_claim="email" \
  allowed_redirect_uris="http://localhost:8250/oidc/callback,https://${VAULT_FQDN}/ui/vault/auth/oidc/oidc/callback" \
  groups_claim="groups" \
  oidc_scopes="profile" \
  policies="default" \
  token_ttl="1h" \
  token_max_ttl="4h"

# Map Entra ID security groups (by Object ID) to Vault policies
OIDC_ACCESSOR=$(vault auth list -format=json | jq -r '."oidc/".accessor')

# Example: Map the "Vault-BU-Finance-Admin" Entra ID group
FINANCE_ADMIN_GROUP_OBJECT_ID="aaaabbbb-cccc-dddd-eeee-ffffffffffff"

EXT_GROUP_ID=$(vault write -format=json identity/group \
  name="ext-entra-finance-admin" \
  type="external" \
  policies="bu-finance-admin" | jq -r '.data.id')

vault write identity/group-alias \
  name="${FINANCE_ADMIN_GROUP_OBJECT_ID}" \
  mount_accessor="${OIDC_ACCESSOR}" \
  canonical_id="${EXT_GROUP_ID}"

# Link to namespace-scoped internal group
vault write -namespace=bu-finance identity/group \
  name="finance-admin" \
  policies="namespace-admin,kv-readwrite,ssh-sign" \
  member_group_ids="${EXT_GROUP_ID}"

echo "OIDC auth configured for Entra ID."

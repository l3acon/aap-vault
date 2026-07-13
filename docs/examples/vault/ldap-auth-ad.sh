#!/bin/bash
# Configure Vault LDAP auth method for on-prem Active Directory.
#
# The key differentiator for AD is the groupfilter using the
# LDAP_MATCHING_RULE_IN_CHAIN OID (1.2.840.113556.1.4.1941)
# which recursively resolves nested group memberships.

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:?Set VAULT_ADDR}"

vault auth enable ldap

vault write auth/ldap/config \
  url="ldaps://dc1.corp.example.com:636" \
  starttls=false \
  insecure_tls=false \
  certificate=@/path/to/ad-ca-cert.pem \
  binddn="cn=vault-svc,ou=ServiceAccounts,dc=corp,dc=example,dc=com" \
  bindpass="${AD_BIND_PASSWORD}" \
  userdn="ou=Employees,dc=corp,dc=example,dc=com" \
  userattr="sAMAccountName" \
  groupdn="dc=corp,dc=example,dc=com" \
  groupfilter="(&(objectClass=group)(member:1.2.840.113556.1.4.1941:={{.UserDN}}))" \
  groupattr="cn" \
  use_token_groups=true \
  max_page_size=1000

# Map AD groups to Vault policies
vault write auth/ldap/groups/Vault-BU-Finance-Admin \
  policies="bu-finance-admin"

vault write auth/ldap/groups/Vault-BU-Engineering-Admin \
  policies="bu-engineering-admin"

vault write auth/ldap/groups/Vault-Platform-Admin \
  policies="vault-admin"

# Cross-namespace mapping via Identity Groups
LDAP_ACCESSOR=$(vault auth list -format=json | jq -r '."ldap/".accessor')

# Create external group linked to AD group
FINANCE_GROUP_ID=$(vault write -format=json identity/group \
  name="ext-finance-admin" \
  type="external" | jq -r '.data.id')

vault write identity/group-alias \
  name="Vault-BU-Finance-Admin" \
  mount_accessor="${LDAP_ACCESSOR}" \
  canonical_id="${FINANCE_GROUP_ID}"

# Create internal group in bu-finance namespace with scoped policies
vault write -namespace=bu-finance identity/group \
  name="finance-admin" \
  policies="namespace-admin,kv-readwrite,ssh-sign" \
  member_group_ids="${FINANCE_GROUP_ID}"

echo "LDAP auth configured for Active Directory."

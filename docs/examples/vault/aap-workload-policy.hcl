# Templated Vault policy for AAP OIDC workload identity.
#
# This single policy handles all business units and job templates.
# Vault resolves {{...}} at token evaluation time using identity
# metadata populated from AAP JWT claim_mappings.
#
# Replace AUTH_JWT_ACCESSOR with the actual accessor ID from:
#   vault auth list -format=json | jq -r '."jwt/".accessor'

# Allow the job to read secrets scoped to its own org and template
path "{{identity.entity.aliases.AUTH_JWT_ACCESSOR.metadata.org}}/kv/data/{{identity.entity.aliases.AUTH_JWT_ACCESSOR.metadata.job_template}}/*" {
  capabilities = ["read", "list"]
}

# Allow the job to read org-wide shared secrets
path "{{identity.entity.aliases.AUTH_JWT_ACCESSOR.metadata.org}}/kv/data/shared/*" {
  capabilities = ["read", "list"]
}

# Allow the job to sign SSH certificates via its org's SSH CA
path "{{identity.entity.aliases.AUTH_JWT_ACCESSOR.metadata.org}}/ssh-ca/sign/automation" {
  capabilities = ["create", "update"]
}

# Allow reading the SSH CA public key (for host bootstrap)
path "{{identity.entity.aliases.AUTH_JWT_ACCESSOR.metadata.org}}/ssh-ca/config/ca" {
  capabilities = ["read"]
}

# Templated Vault policy for AAP OIDC workload identity.
# Rendered by Terraform with the actual JWT auth accessor.

path "{{identity.entity.aliases.${jwt_accessor}.metadata.org}}/kv/data/{{identity.entity.aliases.${jwt_accessor}.metadata.job_template}}/*" {
  capabilities = ["read", "list"]
}

path "{{identity.entity.aliases.${jwt_accessor}.metadata.org}}/kv/data/shared/*" {
  capabilities = ["read", "list"]
}

path "{{identity.entity.aliases.${jwt_accessor}.metadata.org}}/ssh-ca/sign/automation" {
  capabilities = ["create", "update"]
}

path "{{identity.entity.aliases.${jwt_accessor}.metadata.org}}/ssh-ca/config/ca" {
  capabilities = ["read"]
}

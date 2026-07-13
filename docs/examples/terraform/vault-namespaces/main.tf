# Terraform configuration for Vault Enterprise namespace hierarchy.
#
# Creates BU namespaces, SSH CAs, KV engines, and the AAP workload
# identity configuration (JWT auth + templated policy).
#
# Usage:
#   terraform init
#   terraform plan -var-file=prod.tfvars
#   terraform apply -var-file=prod.tfvars

terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "vault" {
  # Configured via VAULT_ADDR and VAULT_TOKEN env vars
}

variable "business_units" {
  description = "Business units to create namespaces for"
  type = list(object({
    name   = string
    teams  = list(string)
    ssh_roles = list(object({
      name          = string
      default_user  = string
      allowed_users = string
      ttl           = string
      max_ttl       = string
    }))
  }))
  default = [
    {
      name  = "bu-finance"
      teams = ["team-payments", "team-risk"]
      ssh_roles = [
        {
          name          = "automation"
          default_user  = "deploy"
          allowed_users = "*"
          ttl           = "5m"
          max_ttl       = "30m"
        },
        {
          name          = "interactive"
          default_user  = "admin"
          allowed_users = "*"
          ttl           = "30m"
          max_ttl       = "4h"
        }
      ]
    },
    {
      name  = "bu-engineering"
      teams = ["team-platform", "team-app-dev"]
      ssh_roles = [
        {
          name          = "automation"
          default_user  = "deploy"
          allowed_users = "*"
          ttl           = "5m"
          max_ttl       = "30m"
        },
        {
          name          = "developer"
          default_user  = "dev-user"
          allowed_users = "*"
          ttl           = "1h"
          max_ttl       = "4h"
        }
      ]
    }
  ]
}

variable "aap_oidc_discovery_url" {
  description = "AAP OIDC discovery URL (e.g., https://aap.example.com/o)"
  type        = string
}

variable "vault_url" {
  description = "Vault server URL for JWT bound_audiences"
  type        = string
}

# --- BU Namespaces ---

resource "vault_namespace" "bu" {
  for_each = { for bu in var.business_units : bu.name => bu }
  path     = each.key
}

resource "vault_namespace" "team" {
  for_each = {
    for pair in flatten([
      for bu in var.business_units : [
        for team in bu.teams : {
          key       = "${bu.name}/${team}"
          namespace = bu.name
          path      = team
        }
      ]
    ]) : pair.key => pair
  }

  namespace = vault_namespace.bu[each.value.namespace].path_fq
  path      = each.value.path
}

# --- SSH CA per BU ---

resource "vault_mount" "ssh_ca" {
  for_each  = { for bu in var.business_units : bu.name => bu }
  namespace = vault_namespace.bu[each.key].path_fq
  path      = "ssh-ca"
  type      = "ssh"
}

resource "vault_ssh_secret_backend_ca" "ca" {
  for_each             = { for bu in var.business_units : bu.name => bu }
  namespace            = vault_namespace.bu[each.key].path_fq
  backend              = vault_mount.ssh_ca[each.key].path
  generate_signing_key = true
}

resource "vault_ssh_secret_backend_role" "roles" {
  for_each = {
    for pair in flatten([
      for bu in var.business_units : [
        for role in bu.ssh_roles : {
          key           = "${bu.name}/${role.name}"
          bu_name       = bu.name
          name          = role.name
          default_user  = role.default_user
          allowed_users = role.allowed_users
          ttl           = role.ttl
          max_ttl       = role.max_ttl
        }
      ]
    ]) : pair.key => pair
  }

  namespace              = vault_namespace.bu[each.value.bu_name].path_fq
  backend                = vault_mount.ssh_ca[each.value.bu_name].path
  name                   = each.value.name
  key_type               = "ca"
  algorithm_signer       = "rsa-sha2-256"
  allow_user_certificates = true
  allowed_users          = each.value.allowed_users
  default_user           = each.value.default_user
  ttl                    = each.value.ttl
  max_ttl                = each.value.max_ttl

  default_extensions = {
    "permit-pty" = ""
  }
}

# --- KV v2 per BU ---

resource "vault_mount" "kv" {
  for_each  = { for bu in var.business_units : bu.name => bu }
  namespace = vault_namespace.bu[each.key].path_fq
  path      = "kv"
  type      = "kv-v2"
}

# --- AAP JWT Auth (root namespace) ---

resource "vault_jwt_auth_backend" "aap" {
  path               = "jwt"
  oidc_discovery_url = var.aap_oidc_discovery_url
}

resource "vault_policy" "aap_workload" {
  name   = "aap-workload-policy"
  policy = templatefile("${path.module}/aap-workload-policy.hcl.tpl", {
    jwt_accessor = vault_jwt_auth_backend.aap.accessor
  })
}

resource "vault_jwt_auth_backend_role" "aap_workload" {
  backend        = vault_jwt_auth_backend.aap.path
  role_name      = "aap-workload-role"
  role_type      = "jwt"
  bound_audiences = [var.vault_url]
  user_claim     = "sub"
  token_ttl      = 300
  token_max_ttl  = 600
  token_policies = [vault_policy.aap_workload.name]

  bound_claims = {
    aap_controller_organization_name = join(",", [for bu in var.business_units : bu.name])
  }

  claim_mappings = {
    aap_controller_organization_name  = "org"
    aap_controller_job_template_name  = "job_template"
    aap_controller_launched_by_name   = "launched_by"
    aap_controller_launch_type        = "launch_type"
  }
}

# --- Outputs ---

output "bu_ssh_ca_public_keys" {
  description = "SSH CA public keys per BU (distribute to hosts)"
  value = {
    for bu_name, ca in vault_ssh_secret_backend_ca.ca :
    bu_name => ca.public_key
  }
}

output "jwt_accessor" {
  description = "JWT auth backend accessor (used in templated policies)"
  value       = vault_jwt_auth_backend.aap.accessor
}

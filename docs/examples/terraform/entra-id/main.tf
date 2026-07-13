# Terraform configuration for Entra ID app registrations and groups.
#
# Creates:
#   - App registration for AAP SAML/OIDC authentication
#   - App registration for Vault OIDC authentication
#   - Security groups following the naming convention
#
# Usage:
#   terraform init
#   terraform plan -var-file=prod.tfvars
#   terraform apply -var-file=prod.tfvars

terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azuread" {
  # Configured via ARM_TENANT_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET
}

variable "aap_url" {
  description = "AAP gateway URL"
  type        = string
}

variable "vault_url" {
  description = "Vault server URL"
  type        = string
}

variable "business_units" {
  description = "Business units and their teams"
  type = list(object({
    name  = string
    teams = list(string)
  }))
}

data "azuread_client_config" "current" {}

# --- AAP App Registration ---

resource "azuread_application" "aap" {
  display_name = "Ansible Automation Platform"
  owners       = [data.azuread_client_config.current.object_id]

  web {
    redirect_uris = [
      "${var.aap_url}/sso/complete/saml/",
      "${var.aap_url}/api/social/complete/azure-ad-oauth2/",
    ]
  }

  group_membership_claims = ["SecurityGroup"]

  optional_claims {
    saml2_token {
      name = "groups"
    }
    id_token {
      name = "groups"
    }
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "98830695-27a2-44f7-8c18-0c3ebc9698f6" # GroupMember.Read.All
      type = "Role"
    }
  }
}

resource "azuread_service_principal" "aap" {
  client_id = azuread_application.aap.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_password" "aap" {
  application_id = azuread_application.aap.id
  display_name   = "AAP SAML/OIDC secret"
}

# --- Vault App Registration ---

resource "azuread_application" "vault" {
  display_name = "HashiCorp Vault"
  owners       = [data.azuread_client_config.current.object_id]

  web {
    redirect_uris = [
      "http://localhost:8250/oidc/callback",
      "${var.vault_url}/ui/vault/auth/oidc/oidc/callback",
    ]
  }

  group_membership_claims = ["SecurityGroup"]

  optional_claims {
    id_token {
      name = "groups"
    }
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "5b567255-7703-4780-807c-7be8301ae99b" # Group.Read.All
      type = "Role"
    }
  }
}

resource "azuread_service_principal" "vault" {
  client_id = azuread_application.vault.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_password" "vault" {
  application_id = azuread_application.vault.id
  display_name   = "Vault OIDC secret"
}

# --- Security Groups ---

# AAP groups (drive org/team membership via authenticator maps)
resource "azuread_group" "aap_teams" {
  for_each = {
    for pair in flatten([
      for bu in var.business_units : [
        for team in bu.teams : {
          key     = "AAP-${bu.name}-${team}"
          bu_name = bu.name
          team    = team
        }
      ]
    ]) : pair.key => pair
  }

  display_name     = each.key
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
}

# Vault groups (drive Vault policy binding via external identity groups)
resource "azuread_group" "vault_admins" {
  for_each = { for bu in var.business_units : bu.name => bu }

  display_name     = "Vault-${each.key}-Admin"
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
}

# Platform admin group
resource "azuread_group" "platform_admin" {
  display_name     = "AAP-Platform-Admin"
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
}

# --- Outputs ---

output "aap_app_client_id" {
  description = "AAP app registration client ID"
  value       = azuread_application.aap.client_id
}

output "aap_app_client_secret" {
  description = "AAP app registration client secret"
  value       = azuread_application_password.aap.value
  sensitive   = true
}

output "vault_app_client_id" {
  description = "Vault app registration client ID"
  value       = azuread_application.vault.client_id
}

output "vault_app_client_secret" {
  description = "Vault app registration client secret"
  value       = azuread_application_password.vault.value
  sensitive   = true
}

output "aap_team_group_ids" {
  description = "AAP team group Object IDs (for authenticator maps)"
  value = {
    for key, group in azuread_group.aap_teams :
    key => group.object_id
  }
}

output "vault_admin_group_ids" {
  description = "Vault admin group Object IDs (for external identity groups)"
  value = {
    for key, group in azuread_group.vault_admins :
    key => group.object_id
  }
}

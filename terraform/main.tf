locals {
  project     = "mtam" # multi-tenant access manager
  environment = var.environment
  location    = var.location

  common_tags = {
    project     = local.project
    environment = local.environment
    owner       = "jordann6"
    managed_by  = "terraform"
  }
}

data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

# --- Resource Group -----------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.project}-${local.environment}"
  location = local.location
  tags     = local.common_tags
}

# Globally-unique suffix for Key Vault names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# --- Platform governance group ------------------------------------------------
# Cross-tenant, read-only access to every tenant vault. This is the central
# governance plane — platform engineers can audit secrets without owning them.

resource "azuread_group" "platform_admins" {
  display_name     = "grp-${local.project}-platform-admins-${local.environment}"
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
}

# --- Per-tenant identity ------------------------------------------------------
# Entra security group = the human/team boundary for a tenant.
# User-assigned managed identity = the workload boundary for a tenant.

resource "azuread_group" "tenant" {
  for_each         = var.tenants
  display_name     = "grp-${local.project}-${each.key}-${local.environment}"
  description      = each.value.description
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
}

resource "azurerm_user_assigned_identity" "tenant" {
  for_each            = var.tenants
  name                = "id-${local.project}-${each.key}-${local.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = merge(local.common_tags, { tenant = each.key })
}

# --- Per-tenant Key Vault -----------------------------------------------------
# One vault per tenant = hard isolation boundary. RBAC authorization only
# (no access policies), so every grant is an auditable Azure role assignment.

resource "azurerm_key_vault" "tenant" {
  for_each                   = var.tenants
  name                       = "kv-${each.key}-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  # Reject plaintext and lock down to the resource owner's tenant
  public_network_access_enabled = true
  tags                          = merge(local.common_tags, { tenant = each.key })
}

# --- RBAC: least-privilege access matrix --------------------------------------

# Deployer (the principal running Terraform) needs Secrets Officer to seed secrets.
resource "azurerm_role_assignment" "deployer_secrets_officer" {
  for_each             = var.tenants
  scope                = azurerm_key_vault.tenant[each.key].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Tenant workload identity → read-only to its OWN vault, nothing else.
resource "azurerm_role_assignment" "tenant_identity_reader" {
  for_each             = var.tenants
  scope                = azurerm_key_vault.tenant[each.key].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.tenant[each.key].principal_id
}

# Tenant team group → manage secrets in its OWN vault.
resource "azurerm_role_assignment" "tenant_group_officer" {
  for_each             = var.tenants
  scope                = azurerm_key_vault.tenant[each.key].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azuread_group.tenant[each.key].object_id
}

# Platform admins → read-only across EVERY tenant vault (central governance).
resource "azurerm_role_assignment" "platform_reader" {
  for_each             = var.tenants
  scope                = azurerm_key_vault.tenant[each.key].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_group.platform_admins.object_id
}

# --- RBAC propagation guard ---------------------------------------------------
# Data-plane role assignments are eventually consistent. Without this, the very
# first secret write can race the Secrets Officer grant and 403. Wait it out.

resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.deployer_secrets_officer]
  create_duration = "60s"
}

# --- Seed secret per tenant ---------------------------------------------------

resource "random_password" "seed" {
  for_each = var.tenants
  length   = var.seed_secret_length
  special  = true
}

resource "azurerm_key_vault_secret" "seed" {
  for_each     = var.tenants
  name         = "${each.key}-app-config"
  value        = random_password.seed[each.key].result
  key_vault_id = azurerm_key_vault.tenant[each.key].id
  content_type = "text/plain"

  depends_on = [time_sleep.rbac_propagation]
}

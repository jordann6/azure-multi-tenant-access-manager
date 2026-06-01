output "resource_group_name" {
  description = "Resource group holding all tenant resources."
  value       = azurerm_resource_group.this.name
}

output "platform_admin_group_object_id" {
  description = "Object ID of the cross-tenant platform-admin governance group."
  value       = azuread_group.platform_admins.object_id
}

output "tenant_key_vault_uris" {
  description = "Per-tenant Key Vault URIs."
  value       = { for k, kv in azurerm_key_vault.tenant : k => kv.vault_uri }
}

output "tenant_identity_client_ids" {
  description = "Per-tenant managed identity client IDs (for workload assignment)."
  value       = { for k, id in azurerm_user_assigned_identity.tenant : k => id.client_id }
}

output "tenant_identity_principal_ids" {
  description = "Per-tenant managed identity principal (object) IDs."
  value       = { for k, id in azurerm_user_assigned_identity.tenant : k => id.principal_id }
}

output "tenant_group_object_ids" {
  description = "Per-tenant Entra security group object IDs."
  value       = { for k, g in azuread_group.tenant : k => g.object_id }
}

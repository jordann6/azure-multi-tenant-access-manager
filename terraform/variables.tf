variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Deployment environment label (dev / prod)."
  type        = string
  default     = "dev"
}

variable "tenants" {
  description = <<-EOT
    Map of onboarded tenants (workload teams). Each key becomes the tenant slug
    used in resource names. Adding or removing an entry onboards or offboards a
    tenant — its isolated Key Vault, managed identity, Entra group, and RBAC
    assignments are created or destroyed as a unit.
  EOT
  type = map(object({
    description = string
  }))
  default = {
    alpha = { description = "Alpha workload team" }
    beta  = { description = "Beta workload team" }
  }

  validation {
    condition     = alltrue([for k in keys(var.tenants) : can(regex("^[a-z0-9]{2,12}$", k))])
    error_message = "Tenant keys must be 2-12 chars, lowercase letters and digits only (used in globally-unique Key Vault names)."
  }
}

variable "seed_secret_length" {
  description = "Length of the auto-generated per-tenant seed secret written to each vault."
  type        = number
  default     = 32
}

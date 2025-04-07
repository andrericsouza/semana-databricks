# Security Configuration for Databricks Platform

# ========== USER GROUPS ==========
# Databricks groups for different user roles
resource "databricks_group" "data_engineers" {
  display_name = "data-engineers"
}

resource "databricks_group" "data_scientists" {
  display_name = "data-scientists"
}

resource "databricks_group" "data_analysts" {
  display_name = "data-analysts"
}

resource "databricks_group" "ml_engineers" {
  display_name = "ml-engineers"
}

# ========== SERVICE PRINCIPALS ==========
# Service principals for automation
resource "databricks_service_principal" "automation" {
  for_each = toset(local.environments)

  display_name = "${local.env_config[each.key].name_prefix}-automation-sp"
  allow_cluster_create = true
}

# ========== PERMISSIONS ==========
# Cluster permissions for different user groups
resource "databricks_permissions" "cluster_usage" {
  for_each = {
    for pair in setproduct(local.environments, ["data_engineers", "data_scientists"]) : "${pair[0]}-${pair[1]}" => {
      env   = pair[0]
      group = pair[1]
    }
  }

  cluster_id = databricks_cluster.job_cluster[each.value.env].id

  access_control {
    group_name       = each.value.group == "data_engineers" ? databricks_group.data_engineers.display_name : databricks_group.data_scientists.display_name
    permission_level = each.value.group == "data_engineers" ? "CAN_RESTART" : "CAN_ATTACH_TO"
  }
}

# SQL warehouse permissions
resource "databricks_permissions" "sql_warehouse_usage" {
  for_each = {
    for pair in setproduct(local.environments, ["data_analysts"]) : "${pair[0]}-${pair[1]}" => {
      env   = pair[0]
      group = pair[1]
    }
  }

  sql_endpoint_id = databricks_sql_endpoint.this[each.value.env].id

  access_control {
    group_name       = databricks_group.data_analysts.display_name
    permission_level = "CAN_USE"
  }
}

# ========== NETWORK SECURITY ==========
# Private endpoints for Databricks UI
resource "azurerm_private_endpoint" "databricks_ui" {
  for_each = var.enable_private_endpoints ? toset(local.environments) : []

  name                = "${local.env_config[each.key].name_prefix}-dbx-ui-pe"
  location            = azurerm_resource_group.this[each.key].location
  resource_group_name = azurerm_resource_group.this[each.key].name
  subnet_id           = azurerm_subnet.private[each.key].id

  private_service_connection {
    name                           = "${local.env_config[each.key].name_prefix}-dbx-ui-psc"
    private_connection_resource_id = azurerm_databricks_workspace.this[each.key].id
    is_manual_connection           = false
    subresource_names              = ["databricks_ui_api"]
  }

  tags = local.env_config[each.key].tags
}

# Private endpoints for Databricks Auth
resource "azurerm_private_endpoint" "databricks_auth" {
  for_each = var.enable_private_endpoints ? toset(local.environments) : []

  name                = "${local.env_config[each.key].name_prefix}-dbx-auth-pe"
  location            = azurerm_resource_group.this[each.key].location
  resource_group_name = azurerm_resource_group.this[each.key].name
  subnet_id           = azurerm_subnet.private[each.key].id

  private_service_connection {
    name                           = "${local.env_config[each.key].name_prefix}-dbx-auth-psc"
    private_connection_resource_id = azurerm_databricks_workspace.this[each.key].id
    is_manual_connection           = false
    subresource_names              = ["databricks_ui_auth"]
  }

  tags = local.env_config[each.key].tags
}

# IP access lists
resource "databricks_ip_access_list" "allowed" {
  for_each = var.enable_private_endpoints ? toset(local.environments) : []

  label                   = "allowed_ips"
  list_type               = "ALLOW"
  ip_addresses            = length(var.bypass_ip_ranges) > 0 ? var.bypass_ip_ranges : ["0.0.0.0/0"]  # Default to allow all if no specific IPs provided
}

# ========== ENCRYPTION ==========
# Customer-managed encryption key
resource "azurerm_key_vault_key" "dbfs_encryption" {
  count = var.enable_customer_managed_keys ? 1 : 0

  name         = "dbfs-encryption-key"
  key_vault_id = azurerm_key_vault.this["prod"].id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]
}

# Outputs have been consolidated in outputs.tf

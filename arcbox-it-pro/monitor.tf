resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags = merge(var.tags, {
        ArcSQLServerExtensionDeployment = "Disabled",
        location = var.location
        })  
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "arc-${random_string.prefix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags = merge(var.tags, {location = var.location})  
}

resource "azapi_resource" "server_workbook" {
  for_each = local.server_workbooks_urls
  type = "Microsoft.Resources/deployments@2024-03-01"
  name = "${each.key}-${random_string.prefix.result}"
  parent_id = azurerm_resource_group.rg.id
  tags = merge(var.tags, {location = var.location})  
  schema_validation_enabled = false
  body = {
    properties = {
      mode = "Incremental"
      templateLink = {
        uri = each.value
      }
      parameters = {}
    }
  }
}

data "http" "sql_dashboards" {
  for_each = local.sql_dashboards_urls
  url = each.value
}

data "jq_query" "sql_arc_dashboards_properties" {
    for_each = local.sql_dashboards_urls
    data = data.http.sql_dashboards[each.key].response_body
    query = ".properties"
}

resource "azapi_resource" "sql_arc_dashboards" {
  for_each = local.sql_dashboards_urls

  type      = "Microsoft.Portal/dashboards@2022-12-01-preview"
  name      = replace(each.key, " ", "")
  parent_id = azurerm_resource_group.rg.id
  location  = azurerm_resource_group.rg.location
  schema_validation_enabled = false
  body = {
    properties = jsondecode(data.jq_query.sql_arc_dashboards_properties[each.key].result)
  }
}

data "http" "sql_workbooks" {
  for_each = local.sql_arc_workbooks_urls
  url = each.value
}

resource "azurerm_application_insights_workbook" "sql_arc_workbooks" {
    for_each = local.sql_arc_workbooks_urls
    name                = uuidv5("url", each.value)
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location
    display_name        = each.key
    tags                = merge(var.tags, {location = var.location})
    data_json           = data.http.sql_workbooks[each.key].response_body
}

resource "azurerm_log_analytics_solution" "log_analytics_solutions" {
  for_each = { for solution in local.log_analytics_solutions : solution => solution }
  solution_name = each.value
  resource_group_name = azurerm_resource_group.rg.name
  location = azurerm_resource_group.rg.location
  tags = merge(var.tags, {location = var.location})
  workspace_resource_id = azurerm_log_analytics_workspace.law.id
  workspace_name = azurerm_log_analytics_workspace.law.name
    plan {
        publisher = "Microsoft"
        product = "OMSGallery/${each.value}"
        promotion_code = ""
    }
}

resource "azapi_resource" "data_collection_rules" {
  depends_on = [ azurerm_log_analytics_solution.log_analytics_solutions ]
  for_each = { for rule in local.arc_flavor : rule => rule }
  type = "Microsoft.Insights/dataCollectionRules@2023-03-11"
  name = each.value
  parent_id = azurerm_resource_group.rg.id
  location = azurerm_resource_group.rg.location
  tags = merge(var.tags, {location = var.location})  
  schema_validation_enabled = false
  body = {
    kind = each.value == "windows" ? "Windows" : each.value == "linux" ? "Linux" : null
    properties = jsondecode(templatefile("${each.value}Dcr.json", {
        LOGANLYTICS_WORKSPACEID = azurerm_log_analytics_workspace.law.id
    }))
  }
}
resource "azapi_resource" "policy_set_definitions" {
  for_each = { for rule in local.arc_flavor : rule => rule }
  type = "Microsoft.Authorization/policySetDefinitions@2023-04-01"
  name = uuidv5("url", "/${each.value}")
  parent_id = data.azurerm_subscription.current.id
  schema_validation_enabled = false
  body = {
    properties = jsondecode(file("${each.value}Policy.json"))    
  }
  response_export_values = ["*"]
}

resource "azapi_resource" "policy_assignments" {
  for_each = { for policy in local.azure_policies : policy.flavor => policy }
  type = "Microsoft.Authorization/policyAssignments@2021-06-01"
  name = "(ArcBox) Policy Assignment for ${each.value.flavor} Servers"
  parent_id = data.azurerm_subscription.current.id
  location = azurerm_resource_group.rg.location
  identity {
    type = "SystemAssigned"
  }  
  schema_validation_enabled = false
  body = {
    properties =  {
      policyDefinitionId = each.value.policy_definition_id
      parameters = each.value.flavor == "windows" ? {
        dcrResourceId = {
          value = azapi_resource.data_collection_rules[each.value.flavor].id
        }
      } : each.value.flavor == "linux" ? {
        dcrResourceId = {
          value = azapi_resource.data_collection_rules[each.value.flavor].id
        }
      } : {
        dcrResourceId = {
          value = azapi_resource.data_collection_rules[each.value.flavor].id
        }
        workspaceRegion = {
          value = azurerm_log_analytics_workspace.law.location
        } 
        workspaceResourceId = {
          value = azurerm_log_analytics_workspace.law.id
        }
      }
    }
  }
}

resource "azapi_resource" "ssh_audit_policy_assignments" {
  type = "Microsoft.Authorization/policyAssignments@2021-06-01"
  name = "(ArcBox) Enable SSH Posture Control audit"
  parent_id = data.azurerm_subscription.current.id
  schema_validation_enabled = false
  body = {
    properties = {
      displayName = "(ArcBox) Enable SSH Posture Control audit"
      description = "Enable SSH Posture Control in audit mode"
      policyDefinitionId = "/providers/Microsoft.Authorization/policyDefinitions/a8f3e6a6-dcd2-434c-b0f7-6f309ce913b4"
      parameters = {
        IncludeArcMachines = {
          value = "true"
        }
      }
    }
  }
}

resource "azurerm_role_assignment" "policy_role_assignment" {
    for_each = azapi_resource.policy_assignments
    scope = data.azurerm_subscription.current.id
    role_definition_name = "Contributor"
    principal_id = azapi_resource.policy_assignments[each.key].identity[0].principal_id
    principal_type = "ServicePrincipal"
}
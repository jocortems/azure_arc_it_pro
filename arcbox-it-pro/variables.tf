variable "location" {
  description = "The Azure region where the resources will be deployed."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group in which the resources will be deployed."
  type        = string
}

variable "tags" {
  description = "A mapping of tags to assign to the resources."
  type        = map(string)
}

locals {
    server_workbooks_urls = {
        arc-server-inventory = "https://raw.githubusercontent.com/microsoft/azure_arc/refs/heads/main/azure_jumpstart_arcbox/artifacts/monitoring/arc-inventory-workbook.json"
        arc-server-performance = "https://raw.githubusercontent.com/microsoft/azure_arc/refs/heads/main/azure_jumpstart_arcbox/artifacts/monitoring/arc-osperformance-workbook.json"
    }

    sql_dashboards_urls = {
        "Arc - Deployment Progress" = "https://raw.githubusercontent.com/microsoft/sql-server-samples/refs/heads/master/samples/features/azure-arc/dashboard/Arc%20-%20Deployment%20Progress.json"
        "Arc - ESU" = "https://raw.githubusercontent.com/microsoft/sql-server-samples/refs/heads/master/samples/features/azure-arc/dashboard/Arc%20-%20ESU.json"
        "Arc - Estate Profile" = "https://raw.githubusercontent.com/microsoft/sql-server-samples/refs/heads/master/samples/features/azure-arc/dashboard/Arc%20-%20Estate%20Profile.json"
        "Arc - Server Deployment" = "https://raw.githubusercontent.com/microsoft/sql-server-samples/refs/heads/master/samples/features/azure-arc/dashboard/Arc%20-%20Server%20Deployment.json"
        "Arc - SQL Server Inventory" = "https://raw.githubusercontent.com/microsoft/sql-server-samples/refs/heads/master/samples/features/azure-arc/dashboard/Arc%20-%20SQL%20Server%20Inventory.json"
        "SQL Server Estate Health" = "https://raw.githubusercontent.com/microsoft/sql-server-samples/refs/heads/master/samples/features/azure-arc/dashboard/SQL%20Server%20Estate%20Health.json"
        "SQL Server Instances" = "https://raw.githubusercontent.com/microsoft/sql-server-samples/refs/heads/master/samples/features/azure-arc/dashboard/SQL%20Server%20Instances.json"
        "Azure Arc Windows and Linux" = "https://raw.githubusercontent.com/weeyin83/Azure-Arc-Windows-Linux-Dashboard/refs/heads/main/Azure-Arc-Windows-Linux-Dashboard.json"
    }

    sql_arc_workbooks_urls = {
        "Azure Arc SQL Databases" = "https://raw.githubusercontent.com/microsoft/sql-server-samples/refs/heads/master/samples/features/azure-arc/workbooks/Azure%20Arc%20Sql%20Databases.workbook"
        "Azure Arc SQL Servers - Best Practices Assessment" = "https://raw.githubusercontent.com/microsoft/sql-server-samples/refs/heads/master/samples/features/azure-arc/workbooks/Azure%20Arc%20Sql%20Servers%20-%20Best%20Practices%20Assessment.workbook"
        "Azure Arc SQL Server Instances" = "https://raw.githubusercontent.com/microsoft/sql-server-samples/refs/heads/master/samples/features/azure-arc/workbooks/Azure%20Arc%20Sql%20Servers.workbook"
    }

    log_analytics_solutions = [
        "ChangeTracking",
        "SQLVulnerabilityAssessment",
        "SQLAdvancedThreatProtection"
    ]

    arc_flavor = [
        "windows",
        "linux",
        "sql"
    ]    

    azure_policies = [ for flavor in local.arc_flavor : 
        {
            flavor                  = flavor
            name                    = azapi_resource.policy_set_definitions[flavor].output.properties.displayName
            policy_definition_id    = azapi_resource.policy_set_definitions[flavor].id
        }
    ]

}
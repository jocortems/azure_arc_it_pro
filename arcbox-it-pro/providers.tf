provider "azurerm" {
  features {
    resource_group {
        prevent_deletion_if_contains_resources = false
    }
  }
}


provider "azuread" {}

provider "azapi" {}

provider "http" {}

provider "jq" {}
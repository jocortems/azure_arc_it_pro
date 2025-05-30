terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source = "hashicorp/azuread"
      version = "~> 2.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "= 2.0.0-beta"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    jq = {
      source  = "massdriver-cloud/jq"
      version = "~> 0.0"
    }
  }
}
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

data "azurerm_subscription" "current" {}

data "azurerm_client_config" "current" {}

data "http" "my_ip" {
  url = "https://ipv4.jsonip.com/"
}

data "jq_query" "my_ip" {
  data = data.http.my_ip.response_body
  query = ".ip"
}

resource "random_string" "prefix" {
  length  = 6
  special = false
  upper   = false
  numeric = false
}
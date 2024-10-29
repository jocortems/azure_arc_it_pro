variable "resource_group_name" {
  description = "The name of the resource group in which the Azure Arc enabled servers should be created."
  type        = string
}

variable "region" {
  description = "The Azure region in which the Azure Arc enabled servers should be created."
  type        = string
}

variable "vnet_cidr" {
  description = "The CIDR block for the virtual network."
  type        = list(string)
  default    = ["192.168.0.0/16"]
}

variable "vm_admin_username" {
  description = "The username for the virtual machine."
  type        = string
}

variable "vm_admin_password" {
  description = "The password for the virtual machine."
  type        = string
}

variable "template_base_url" {
  description = "The base URL for the Azure Arc enabled server template."
  type        = string
  default    = "https://raw.githubusercontent.com/jocortems/refs/heads/main/azure_arc_itpro/main/onprem-arc"
}

variable "vm_autologon" {
  description = "Enable autologon for the virtual machine."
  type        = bool
  default    = true
}

variable "naming_prefix" {
  description = "The prefix to use for naming resources."
  type        = string
  default    = "ArcBox"  
}

variable "debug_enabled" {
  description = "Enable debug output for bootstrap script."
  type        = bool
  default     = true
}

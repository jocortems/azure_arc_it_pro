resource "azurerm_resource_group" "rg" {
  name      = format("%s-%s", var.resource_group_name, random_string.prefix.result)
  location  = var.region
}

resource "azurerm_virtual_network" "vnet" {
  name                = format("arc-vnet-%s", random_string.prefix.result)
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.vnet_cidr
}

resource "azurerm_subnet" "subnet" {
  name                 = "Arc-VM"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr[0], 8, 0)]
  default_outbound_access_enabled = false
}


# Create virtual machines

resource "azurerm_public_ip" "vm_ip" {
  name                = format("vm-ip-%s", random_string.prefix.result)
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_managed_disk" "arc_data_disk" {
    name = "arc-data-disk-${random_string.prefix.result}"
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    storage_account_type = "PremiumV2_LRS"
    create_option = "Empty"
    disk_size_gb = 1024
}


resource "azurerm_network_interface" "nic" {
  name                              = "nic-${random_string.prefix.result}"
  location                          = azurerm_resource_group.rg.location
  resource_group_name               = azurerm_resource_group.rg.name
  accelerated_networking_enabled    = true

  ip_configuration {
    name                            = "ipconfig"
    subnet_id                       = azurerm_subnet.subnet.id
    private_ip_address_allocation   = "Static"
    private_ip_address              = cidrhost(azurerm_subnet.subnet.address_prefixes[0], 10)
    primary                         = true
    public_ip_address_id            = azurerm_public_ip.vm_ip.id
  }
}

resource "azurerm_windows_virtual_machine" "arc_machine" {
    name                  = "arc-vm-${random_string.prefix.result}"
    resource_group_name   = azurerm_resource_group.rg.name
    location              = azurerm_resource_group.rg.location
    size                  = "Standard_D48ads_v5"
    admin_username        = var.vm_admin_username
    admin_password        = var.vm_admin_password
    network_interface_ids = [azurerm_network_interface.nic.id]
    provision_vm_agent    = true
    zone                  = "1"

    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "MicrosoftWindowsServer"
        offer     = "WindowsServer"
        sku       = "2025-datacenter-g2"
        version   = "latest"
    }    
}

resource "azurerm_virtual_machine_data_disk_attachment" "arc_data_disk_attachment" {
    managed_disk_id    = azurerm_managed_disk.arc_data_disk.id
    virtual_machine_id = azurerm_windows_virtual_machine.arc_machine.id
    lun                = 0
    caching            = "ReadWrite"
}

resource "azurerm_virtual_machine_extension" "arc_machine_extension" {
  name                        = "Bootstrap"
  virtual_machine_id          = azurerm_windows_virtual_machine.arc_machine.id
  publisher                   = "Microsoft.Compute"
  type                        = "CustomScriptExtension"
  type_handler_version        = "1.10"
  auto_upgrade_minor_version  = true

  protected_settings = <<PROTECTED_SETTINGS
    {
      "fileUris": [
        "${var.template_base_url}/artifacts/Bootstrap.ps1"
      ],
      "commandToExecute": "powershell.exe -ExecutionPolicy Bypass -File Bootstrap.ps1 -adminUsername ${var.vm_admin_username} -adminPassword ${var.vm_admin_password} -acceptEula \"yes\" -templateBaseUrl ${var.template_base_url} -rdpPort 3389 -vmAutologon ${var.vm_autologon} -namingPrefix ${var.naming_prefix} -debugEnabled ${var.debug_enabled}"
    }
  PROTECTED_SETTINGS
}

resource "azurerm_network_security_group" "arc_nsg" {
  name                = "arc-nsg-${random_string.prefix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowMyIp"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

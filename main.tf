# Configure the Azure Provider
provider "azurerm" {
  # whilst the `version` attribute is optional, we recommend pinning to a given version of the Provider
  # version = "=1.36.0"
}

# Create a resource group
resource "azurerm_resource_group" "kiyot" {
  name     = "${var.prefix}-kiyot"
  location = "East US"
}

# Create a virtual network within the resource group
resource "azurerm_virtual_network" "kiyot-vnet" {
  name                = "kiyot-virtual-network"
  resource_group_name = "${azurerm_resource_group.kiyot.name}"
  location            = "${azurerm_resource_group.kiyot.location}"
  address_space       = ["172.20.0.0/16"]
}

resource "azurerm_subnet" "kiyot-subnet" {
  name                 = "internal"
  resource_group_name  = "${azurerm_resource_group.kiyot.name}"
  virtual_network_name = "${azurerm_virtual_network.kiyot-vnet.name}"
  address_prefix       = "172.20.0.0/24"
}

resource "azurerm_route_table" "kiyot-rt" {
  name                          = "kiyot-routetable"
  location                      = "${azurerm_resource_group.kiyot.location}"
  resource_group_name           = "${azurerm_resource_group.kiyot.name}"
  disable_bgp_route_propagation = false

  route {
    name           = "route1"
    address_prefix = "10.0.0.0/16"
    next_hop_type  = "vnetlocal"
  }
  
  # tags = {
  #   environment = "Production"
  # }
}

resource "azurerm_subnet_route_table_association" "kiyot-rt-assoc" {
  subnet_id      = "${azurerm_subnet.kiyot-subnet.id}"
  route_table_id = "${azurerm_route_table.kiyot-rt.id}"
}

resource "azurerm_public_ip" "master-ip" {
  name                = "${var.prefix}-master-ip"
  location            = "${azurerm_resource_group.kiyot.location}"
  resource_group_name = "${azurerm_resource_group.kiyot.name}"
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "master-nic" {
  name                = "${var.prefix}-master-nic"
  location            = "${azurerm_resource_group.kiyot.location}"
  resource_group_name = "${azurerm_resource_group.kiyot.name}"

  ip_configuration {
    name                          = "${var.prefix}-master-nic"
    subnet_id                     = "${azurerm_subnet.kiyot-subnet.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.master-ip.id}"
  }
}

resource "azurerm_virtual_machine" "k8s-master" {
  name                  = "${var.prefix}-k8s-master"
  location              = "${azurerm_resource_group.kiyot.location}"
  resource_group_name   = "${azurerm_resource_group.kiyot.name}"
  network_interface_ids = ["${azurerm_network_interface.master-nic.id}"]
  vm_size               = "Standard_DS1_v2"

  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "master"
    admin_username = "ubuntu"
    # admin_password = ""
  }
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = file("${var.ssh-key-path}")
      path = "/home/ubuntu/.ssh/authorized_keys"
    }    
  }
  tags = {
    environment = "kiyot"
  }
}

resource "azurerm_public_ip" "worker-ip" {
  name                = "${var.prefix}-worker-ip"
  location            = "${azurerm_resource_group.kiyot.location}"
  resource_group_name = "${azurerm_resource_group.kiyot.name}"
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "kiyot-worker-nic" {
  name                = "${var.prefix}-kiyot-worker-nic"
  location            = "${azurerm_resource_group.kiyot.location}"
  resource_group_name = "${azurerm_resource_group.kiyot.name}"

  ip_configuration {
    name                          = "${var.prefix}-kiyot-worker-nic"
    subnet_id                     = "${azurerm_subnet.kiyot-subnet.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.worker-ip.id}"
  }
}


resource "azurerm_virtual_machine" "k8s-worker" {
  name                  = "${var.prefix}-k8s-worker"
  location              = "${azurerm_resource_group.kiyot.location}"
  resource_group_name   = "${azurerm_resource_group.kiyot.name}"
  network_interface_ids = ["${azurerm_network_interface.kiyot-worker-nic.id}"]
  vm_size               = "Standard_DS1_v2"

  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "workerdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "kiyotworker"
    admin_username = "ubuntu"
    # admin_password = ""
  }
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = file("${var.ssh-key-path}")
      path = "/home/ubuntu/.ssh/authorized_keys"
    }    
  }
  tags = {
    environment = "kiyot"
  }
}

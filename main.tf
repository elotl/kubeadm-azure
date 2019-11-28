# Configure the Azure Provider
provider "azurerm" {
  # whilst the `version` attribute is optional, we recommend pinning to a given version of the Provider
  # version = "=1.36.0"
}

# Create a resource group
resource "azurerm_resource_group" "kiyot" {
  name     = "${var.cluster-name}-kiyot"
  location = var.region
}

# Create a virtual network within the resource group
resource "azurerm_virtual_network" "kiyot-vnet" {
  name                = "kiyot-virtual-network"
  resource_group_name = "${azurerm_resource_group.kiyot.name}"
  location            = "${azurerm_resource_group.kiyot.location}"
  address_space       = [var.vpc-cidr]
}

resource "azurerm_subnet" "kiyot-subnet" {
  name                 = "internal"
  resource_group_name  = "${azurerm_resource_group.kiyot.name}"
  virtual_network_name = "${azurerm_virtual_network.kiyot-vnet.name}"
  address_prefix       = cidrsubnet(var.vpc-cidr, 4, 0)
}

resource "azurerm_route_table" "kiyot-rt" {
  name                          = "kiyot-routetable"
  location                      = "${azurerm_resource_group.kiyot.location}"
  resource_group_name           = "${azurerm_resource_group.kiyot.name}"
  disable_bgp_route_propagation = false

  route {
    name           = "route1"
    address_prefix = var.vpc-cidr
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
  name                = "${var.cluster-name}-master-ip"
  location            = "${azurerm_resource_group.kiyot.location}"
  resource_group_name = "${azurerm_resource_group.kiyot.name}"
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "master-nic" {
  name                = "${var.cluster-name}-master-nic"
  location            = "${azurerm_resource_group.kiyot.location}"
  resource_group_name = "${azurerm_resource_group.kiyot.name}"

  ip_configuration {
    name                          = "${var.cluster-name}-master-nic"
    subnet_id                     = "${azurerm_subnet.kiyot-subnet.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.master-ip.id}"
  }
}

resource "azurerm_virtual_machine" "k8s-master" {
  name                  = "${var.cluster-name}-k8s-master"
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
    custom_data = data.template_file.master-userdata.rendered
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
  name                = "${var.cluster-name}-worker-ip"
  location            = "${azurerm_resource_group.kiyot.location}"
  resource_group_name = "${azurerm_resource_group.kiyot.name}"
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "kiyot-worker-nic" {
  name                = "${var.cluster-name}-kiyot-worker-nic"
  location            = "${azurerm_resource_group.kiyot.location}"
  resource_group_name = "${azurerm_resource_group.kiyot.name}"

  ip_configuration {
    name                          = "${var.cluster-name}-kiyot-worker-nic"
    subnet_id                     = "${azurerm_subnet.kiyot-subnet.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.worker-ip.id}"
  }
}


resource "azurerm_virtual_machine" "k8s-worker" {
  name                  = "${var.cluster-name}-k8s-worker"
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
    custom_data = data.template_file.milpa-worker-userdata.rendered
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

resource "random_id" "k8stoken-prefix" {
  byte_length = 3
}

resource "random_id" "k8stoken-suffix" {
  byte_length = 8
}

locals {
  k8stoken = format(
    "%s.%s",
    random_id.k8stoken-prefix.hex,
    random_id.k8stoken-suffix.hex,
  )
}

data "template_file" "master-userdata" {
  template = file(var.master-userdata)

  vars = {
    k8stoken                = local.k8stoken
    k8s_version             = var.k8s-version
    pod_cidr                = var.pod-cidr
    service_cidr            = var.service-cidr
    subnet_cidrs            = azurerm_subnet.kiyot-subnet.address_prefix
    node_nametag            = var.cluster-name
    default_instance_type   = var.default-instance-type
    default_volume_size     = var.default-volume-size
    boot_image_tags         = jsonencode(var.boot-image-tags)
    license_key             = var.license-key
    license_id              = var.license-id
    license_username        = var.license-username
    license_password        = var.license-password
    itzo_url                = var.itzo-url
    itzo_version            = var.itzo-version
    milpa_image             = var.milpa-image
    network_plugin          = var.network-plugin
    configure_cloud_routes  = var.configure-cloud-routes
  }
}

data "template_file" "milpa-worker-userdata" {
  template = file(var.milpa-worker-userdata)

  vars = {
    k8stoken        = local.k8stoken
    k8s_version     = var.k8s-version
    masterIP        = azurerm_network_interface.master-nic.private_ip_address
    network_plugin  = var.network-plugin
  }
}
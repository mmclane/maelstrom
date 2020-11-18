/*-----------------------------------------------*/
/* Create Provider resource                      */
/*-----------------------------------------------*/
provider "azurerm" {
  version = "~> 1.16"
}

provider "local" {
  version = "~> 1.1"
}

provider "template" {
  version = "~> 1.0"
}

/*-----------------------------------------------*/
/* Common Resources                              */
/*-----------------------------------------------*/

resource "azurerm_resource_group" "test_rg" {
  name     = "${var.project-name}_${var.run_id}"
  location = "${var.region}"

  tags {
    ManagedBy = "Terraform"
    Project   = "${var.tag-project}"
    RemoveBy  = "${timeadd(timestamp(), var.cleanup_wait)}"
    RunId     = "${var.run_id}"
    Team      = "cbs-devops"
  }
}

resource "azurerm_virtual_network" "test_net" {
  name                = "${var.project-name}_${var.run_id}_network"
  resource_group_name = "${azurerm_resource_group.test_rg.name}"
  location            = "${var.region}"

  address_space = ["${var.network_cidr}"]

  tags {
    ManagedBy = "Terraform"
    Project   = "${var.tag-project}"
    RemoveBy  = "${timeadd(timestamp(), var.cleanup_wait)}"
    RunId     = "${var.run_id}"
    Team      = "cbs-devops"
  }
}

resource "azurerm_subnet" "test_subnet" {
  name                 = "${var.project-name}_${var.run_id}_subnet"
  resource_group_name  = "${azurerm_resource_group.test_rg.name}"
  virtual_network_name = "${azurerm_virtual_network.test_net.name}"
  address_prefix       = "${var.network_cidr}"
}

resource "azurerm_storage_queue" "test_queue" {
  name                 = "test-${var.run_id}"
  storage_account_name = "${data.azurerm_storage_account.sa.name}"
  resource_group_name  = "${data.azurerm_resource_group.maelstrom.name}"
}

resource "azurerm_network_security_group" "vmsg" {
  name                = "${var.run_id}-vm-security-group"
  location            = "${var.region}"
  resource_group_name = "${azurerm_resource_group.test_rg.name}"

  tags {
    Team      = "cbs-devops"
    ManagedBy = "Terraform"
    Project   = "${var.tag-project}"
    RemoveBy  = "${timeadd(timestamp(), var.cleanup_wait)}"
    RunId     = "${var.run_id}"
  }
}

resource "azurerm_network_security_rule" "criteo_allow_all" {
  name                        = "criteo_allow_all"
  priority                    = 100
  direction                   = "Inbound"
  resource_group_name         = "${azurerm_resource_group.test_rg.name}"
  access                      = "Allow"
  protocol                    = "Tcp"
  destination_port_range      = "*"
  source_port_range           = "*"
  source_address_prefixes     = ["${var.criteo_ips}"]
  destination_address_prefix  = "*"
  network_security_group_name = "${azurerm_network_security_group.vmsg.name}"
}

/*-----------------------------------------------*/
/* Slave Resources                               */
/*-----------------------------------------------*/
resource "azurerm_network_interface" "slave" {
  name                      = "${var.run_id}-jmeter_slave-${count.index}"
  location                  = "${var.region}"
  resource_group_name       = "${azurerm_resource_group.test_rg.name}"
  network_security_group_id = "${azurerm_network_security_group.vmsg.id}"

  ip_configuration = {
    name      = "${var.run_id}-slave-${count.index}"
    subnet_id = "${azurerm_subnet.test_subnet.id}"

    private_ip_address_allocation = "dynamic"
  }

  tags {
    Team      = "cbs-devops"
    ManagedBy = "Terraform"
    Project   = "${var.tag-project}"
    RemoveBy  = "${timeadd(timestamp(), var.cleanup_wait)}"
    RunId     = "${var.run_id}"
  }

  count = "${var.slave_count}"
}

resource "azurerm_virtual_machine" "slave" {
  name                             = "${var.run_id}-jmeter_slave-${count.index}"
  location                         = "${var.region}"
  resource_group_name              = "${azurerm_resource_group.test_rg.name}"
  network_interface_ids            = ["${element(azurerm_network_interface.slave.*.id, count.index)}"]
  vm_size                          = "${var.slave_size}"
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    id = "${data.azurerm_shared_image.jmeter-node.id}"
  }

  storage_os_disk {
    name              = "${var.run_id}-osdisk-slave-${count.index}"
    disk_size_gb      = "50"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "jmeter-slave-${count.index}"
    admin_username = "${var.admin_name}"
    custom_data    = "${data.template_file.slave_script.rendered}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      "path"     = "/home/${var.admin_name}/.ssh/authorized_keys"
      "key_data" = "${data.local_file.admin_key.content}"
    }
  }

  tags {
    Team      = "cbs-devops"
    ManagedBy = "Terraform"
    Project   = "${var.tag-project}"
    RemoveBy  = "${timeadd(timestamp(), var.cleanup_wait)}"
    RunId     = "${var.run_id}"
  }

  count = "${var.slave_count}"
}

/*-----------------------------------------------*/
/* Master Resources                              */
/*-----------------------------------------------*/
resource "azurerm_network_interface" "master" {
  name                      = "${var.run_id}-jmeter_master"
  location                  = "${var.region}"
  resource_group_name       = "${azurerm_resource_group.test_rg.name}"
  network_security_group_id = "${azurerm_network_security_group.vmsg.id}"

  ip_configuration = {
    name                          = "${var.run_id}-master"
    subnet_id                     = "${azurerm_subnet.test_subnet.id}"
    private_ip_address_allocation = "dynamic"
  }

  tags {
    Team      = "cbs-devops"
    ManagedBy = "Terraform"
    Project   = "${var.tag-project}"
    RemoveBy  = "${timeadd(timestamp(), var.cleanup_wait)}"
    RunId     = "${var.run_id}"
  }
}

resource "azurerm_virtual_machine" "master" {
  name                             = "${var.run_id}-jmeter_master"
  location                         = "${var.region}"
  resource_group_name              = "${azurerm_resource_group.test_rg.name}"
  network_interface_ids            = ["${azurerm_network_interface.master.id}"]
  vm_size                          = "${var.master_size}"
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    id = "${data.azurerm_shared_image.jmeter-node.id}"
  }

  storage_os_disk {
    name              = "${var.run_id}-osdisk-master"
    disk_size_gb      = "50"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "jmeter-master"
    admin_username = "${var.admin_name}"

    custom_data = "${data.template_file.jmeter_master_bootstrap.rendered}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      "path"     = "/home/${var.admin_name}/.ssh/authorized_keys"
      "key_data" = "${data.local_file.admin_key.content}"
    }
  }

  tags {
    Team      = "cbs-devops"
    ManagedBy = "Terraform"
    Project   = "${var.tag-project}"
    RemoveBy  = "${timeadd(timestamp(), var.cleanup_wait)}"
    RunId     = "${var.run_id}"
  }
}

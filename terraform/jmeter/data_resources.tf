data "azurerm_resource_group" "storage" {
  name = "storageaccounts-prod"
}

data "azurerm_resource_group" "maelstrom" {
  name = "maelstrom-${var.env}"
}

data "azurerm_shared_image" "jmeter-node" {
  name                = "jmeter-prod"
  gallery_name        = "image_gallery_prod"
  resource_group_name = "shared_image_gallery-prod"
  location            = "${var.region}"
  os_type             = "Linux"

  identifier {
    publisher = "criteo"
    offer     = "centos"
    sku       = "jmeter-prod"
  }
}

data "template_file" "slave_script" {
  template = "${file("${path.module}/jmeter-slave.py")}"

  vars {
    uuid        = "${var.run_id}"
    conn_string = "${data.azurerm_storage_account.sa.primary_connection_string}"
  }
}

data "template_file" "jmeter_master_bootstrap" {
  template = "${file("${path.module}/jmeter-master.py")}"

  vars {
    slave_ips_array = "${jsonencode(azurerm_network_interface.slave.*.private_ip_address)}"
    slave_count     = "${var.slave_count}"
    conn_string     = "${data.azurerm_storage_account.sa.primary_connection_string}"
    uuid            = "${var.run_id}"
    master_priv_ip  = "${azurerm_network_interface.master.private_ip_address}"
  }
}

data "local_file" "admin_key" {
  filename = "${path.module}/keys/lots.pub"
}

data "azurerm_storage_account" "sa" {
  name                = "maelstrom${var.env}"
  resource_group_name = "${data.azurerm_resource_group.maelstrom.name}"
}

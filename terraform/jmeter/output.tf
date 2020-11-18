output "master_private_ip" {
  value = "${azurerm_network_interface.master.private_ip_address}"
}

output "slave_private_ips" {
  value = "${join(",", azurerm_network_interface.slave.*.private_ip_address)}"
}

# Uncomment to troubleshootmaster master bootstrap script.
# output "z_script" {
#   value = "${data.template_file.jmeter_master_bootstrap.rendered}"
# }


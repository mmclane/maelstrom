# The following Environment Variables must be set:
# ARM_ACCESS_KEY - Access Key for the storage account where the terraform state files are stored.
# ARM_CLIENT_ID - Used by the azurerm provider
# ARM_CLIENT_SECRET - Used by the azurerm provider
# ARM_SUBSCRIPTION_ID - Used by the azurerm provider
# ARM_TENANT_ID - Used by the azurerm provider

variable "project-name" {
  default = "maelstrom"
}

variable "criteo_ips" {
  type    = "list"
  default = ["172.28.0.0/15", "10.0.0.0/8", "172.31.0.0/16", "192.168.0.0/16"]
}

# Tag Variables
variable "tag-project" {
  default = "maelstrom"
}

# OS username
variable "admin_name" {
  default = "devops"
}

variable "env" {
  type    = "string"
  default = "prod"
}

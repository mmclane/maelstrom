variable "run_id" {
  type = "string"
}

variable "cleanup_wait" {
  type    = "string"
  default = "24h"
}

variable "slave_count" {
  type = "string"
}

variable "slave_size" {
  type    = "string"
  default = "Standard_F2s_v2"
}

variable "master_size" {
  type    = "string"
  default = "Standard_F2s_v2"
}

// Until this no longer depends on criteo networks anything
// Other than EastUS will break fail. However, since this is
// Strictly controlled via our webconsole and we are only allowing
// EastUS currently this should not be an issue
variable "region" {
  description = "Set region to run test out of"
  type        = "string"
}

// Gonna be honest I just picked a random CIDR here
variable "network_cidr" {
  description = "CIDR block to create the network for the test"
  type        = "string"
  default     = "10.6.2.0/24"
}

# Fixture for examples/Jenkinsfile.terraform.
#
# Deliberately has no provider requirements so `terraform init` works offline and
# the example never downloads anything. It exercises variables, locals and
# outputs — enough for `terraform validate` to be meaningful.

terraform {
  required_version = ">= 1.6.0"
}

variable "environment" {
  description = "Logical environment name."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

locals {
  tags = {
    environment = var.environment
    managed_by  = "jenkins"
    component   = "terraform-validate-fixture"
  }
}

output "tags" {
  description = "Tags a real module would apply to its resources."
  value       = local.tags
}

variable "aws_region" {
  description = "AWS region used for the development environment."
  type        = string
  default     = "us-east-2"

  validation {
    condition = contains(
      [
        "us-east-2",
        "ca-central-1",
        "ca-west-1"
      ],
      var.aws_region
    )

    error_message = "AWS region must be us-east-2, ca-central-1, or ca-west-1."
  }
}

variable "environment" {
  description = "Name of the deployment environment."
  type        = string
  default     = "dev"

  validation {
    condition     = var.environment == "dev"
    error_message = "This root module supports only the dev environment."
  }
}

variable "expected_account_id" {
  description = "AWS account authorized for this lab. The provider rejects other accounts."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "Expected AWS account ID must contain exactly 12 digits."
  }
}

variable "allow_force_destroy" {
  description = "Explicitly allow deletion of all bucket contents during lab teardown."
  type        = bool
  default     = false
  nullable    = false
}

variable "administrator_role_name" {
  description = "Existing same-account role that retains key administration and can assume the bounded workload roles."
  type        = string
  default     = "CloudAdministratorRole"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.administrator_role_name))
    error_message = "Administrator role name must be a valid IAM role name without a path."
  }
}

variable "workload_prefix" {
  description = "Only this object prefix is accessible to the reader/writer roles."
  type        = string
  default     = "workloads/"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9/_-]*/$", var.workload_prefix))
    error_message = "Workload prefix must be a relative lowercase prefix ending in /, without wildcards."
  }
}

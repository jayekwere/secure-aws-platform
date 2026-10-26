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

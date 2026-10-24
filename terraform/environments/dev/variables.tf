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
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be dev, test, or prod."
  }
}

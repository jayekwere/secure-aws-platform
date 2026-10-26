variable "expected_account_id" {
  description = "Account authorized for the state and access-log foundation."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "Expected AWS account ID must contain exactly 12 digits."
  }
}

variable "aws_region" {
  description = "Region shared by the development bucket, state, and access-log destination."
  type        = string
  default     = "us-east-2"
  validation {
    condition     = contains(["us-east-2", "ca-central-1", "ca-west-1"], var.aws_region)
    error_message = "Unsupported lab region."
  }
}

variable "administrator_role_name" {
  description = "Existing same-account state/key administrator."
  type        = string
  default     = "CloudAdministratorRole"
  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.administrator_role_name))
    error_message = "Administrator role name must be a valid IAM role name without a path."
  }
}

variable "data_bucket_name" {
  description = "Existing development data bucket; used to bound S3 log-delivery permissions."
  type        = string
  validation {
    condition     = startswith(var.data_bucket_name, "secure-aws-platform-dev-") && length(var.data_bucket_name) <= 57
    error_message = "Provide the existing project development bucket name (57 characters or fewer)."
  }
}

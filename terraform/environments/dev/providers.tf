provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "secure-aws-platform"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "secure-aws-platform"
    }
  }
}

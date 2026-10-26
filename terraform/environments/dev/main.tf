resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  bucket_name = "secure-aws-platform-${var.environment}-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket" "secure_data" {
  #checkov:skip=CKV_AWS_18:Access logging will use a dedicated log bucket during the centralized logging phase.
  #checkov:skip=CKV2_AWS_62:EventBridge notifications will be implemented during the event-driven remediation phase.
  #checkov:skip=CKV_AWS_144:Cross-region replication is not required for this temporary single-region development lab.

  bucket        = local.bucket_name
  force_destroy = var.allow_force_destroy

  tags = {
    Name               = local.bucket_name
    Purpose            = "Cloud security learning project"
    DataClassification = "Internal"
  }
}

resource "aws_s3_bucket_public_access_block" "secure_data" {
  bucket = aws_s3_bucket.secure_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "secure_data" {
  bucket = aws_s3_bucket.secure_data.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "secure_data" {
  bucket = aws_s3_bucket.secure_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secure_data" {
  bucket = aws_s3_bucket.secure_data.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.secure_data.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_account_id]
  default_tags {
    tags = {
      Project     = "secure-aws-platform"
      Environment = "dev"
      ManagedBy   = "Terraform"
      Purpose     = "State and access-log foundation"
    }
  }
}

locals {
  root_arn               = format("arn:aws:iam::%s:root", var.expected_account_id)
  administrator_role_arn = format("arn:aws:iam::%s:role/%s", var.expected_account_id, var.administrator_role_name)
  state_bucket_name      = format("secure-aws-platform-state-%s-%s", var.expected_account_id, var.aws_region)
  access_logs_name       = format("secure-aws-platform-access-%s-%s", var.expected_account_id, var.aws_region)
  state_bucket_arn       = format("arn:aws:s3:::%s", local.state_bucket_name)
  s3_service             = format("s3.%s.amazonaws.com", var.aws_region)
  state_keys             = ["environments/dev/terraform.tfstate", "bootstrap/terraform.tfstate"]
  administrator_arns     = [local.administrator_role_arn, local.root_arn]
  log_source_arns = [
    local.state_bucket_arn,
    format("arn:aws:s3:::%s", var.data_bucket_name),
    format("arn:aws:s3:::%s-audit", var.data_bucket_name),
  ]
}

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_144:Single-region lab state uses versioning and explicit recovery tests; cross-region replication is outside this milestone.
  bucket        = local.state_bucket_name
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket" "access_logs" {
  #checkov:skip=CKV_AWS_18:This is the terminal access-log destination; logging it into itself would create recursion.
  #checkov:skip=CKV_AWS_145:S3 server-access-log delivery requires an SSE-S3 destination; source-account/ARN policies, public blocking, TLS and versioning compensate.
  #checkov:skip=CKV_AWS_144:Replication is not required for the temporary single-region log archive.
  #checkov:skip=CKV2_AWS_62:Log-object notifications are intentionally omitted; CloudTrail/EventBridge monitors bucket management changes.
  bucket        = local.access_logs_name
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kms_key" "state" {
  description                        = "Encrypts project Terraform state and native lockfiles"
  deletion_window_in_days            = 30
  enable_key_rotation                = true
  bypass_policy_lockout_safety_check = false
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RootRecoveryOnly"
        Effect    = "Allow"
        Principal = { AWS = local.root_arn }
        Action    = ["kms:DescribeKey", "kms:GetKeyPolicy", "kms:PutKeyPolicy"]
        Resource  = "*"
        Condition = { ArnEquals = { "aws:PrincipalArn" = local.root_arn } }
      },
      {
        Sid       = "NamedStateKeyAdministrator"
        Effect    = "Allow"
        Principal = { AWS = local.administrator_role_arn }
        Action = [
          "kms:DescribeKey", "kms:GetKeyPolicy", "kms:PutKeyPolicy",
          "kms:CreateAlias", "kms:UpdateAlias", "kms:DeleteAlias",
          "kms:ListResourceTags", "kms:TagResource", "kms:UntagResource",
          "kms:EnableKeyRotation", "kms:DisableKeyRotation", "kms:GetKeyRotationStatus",
          "kms:UpdateKeyDescription", "kms:EnableKey", "kms:DisableKey",
          "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:ListGrants", "kms:RevokeGrant",
        ]
        Resource = "*"
      },
      {
        Sid       = "StateCryptographyThroughS3Only"
        Effect    = "Allow"
        Principal = { AWS = local.administrator_role_arn }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
        Resource  = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = local.s3_service }
          StringLike = {
            "kms:EncryptionContext:aws:s3:arn" = [local.state_bucket_arn, format("%s/*", local.state_bucket_arn)]
          }
        }
      },
    ]
  })
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "state" {
  name          = "alias/secure-aws-platform-state"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.state.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.state_bucket_arn, format("%s/*", local.state_bucket_arn)]
        Condition = { Bool = { "aws:SecureTransport" = "false", "aws:PrincipalIsAWSService" = "false" } }
      },
      {
        Sid       = "DenyOtherPrincipals"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.state_bucket_arn, format("%s/*", local.state_bucket_arn)]
        Condition = { ArnNotEquals = { "aws:PrincipalArn" = local.administrator_arns } }
      },
      {
        Sid       = "RequireKmsEncryption"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = format("%s/*", local.state_bucket_arn)
        Condition = { StringNotEquals = { "s3:x-amz-server-side-encryption" = "aws:kms" } }
      },
      {
        Sid       = "RequireStateKey"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = format("%s/*", local.state_bucket_arn)
        Condition = { StringNotEquals = { "s3:x-amz-server-side-encryption-aws-kms-key-id" = aws_kms_key.state.arn } }
      },
      {
        Sid       = "ProtectStateVersions"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
        Resource  = [for key in local.state_keys : format("%s/%s", local.state_bucket_arn, key)]
      },
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.state]
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.access_logs.arn, format("%s/*", aws_s3_bucket.access_logs.arn)]
        Condition = { Bool = { "aws:SecureTransport" = "false", "aws:PrincipalIsAWSService" = "false" } }
      },
      {
        Sid       = "RestrictHumanAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.access_logs.arn, format("%s/*", aws_s3_bucket.access_logs.arn)]
        Condition = {
          ArnNotEquals = { "aws:PrincipalArn" = local.administrator_arns }
          Bool         = { "aws:PrincipalIsAWSService" = "false" }
        }
      },
      {
        Sid       = "BoundedS3AccessLogDelivery"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = format("%s/s3-access/*", aws_s3_bucket.access_logs.arn)
        Condition = {
          StringEquals = { "aws:SourceAccount" = var.expected_account_id }
          ArnLike      = { "aws:SourceArn" = local.log_source_arns }
        }
      },
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.access_logs]
}

resource "aws_s3_bucket_logging" "state" {
  bucket        = aws_s3_bucket.state.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "s3-access/state/"
  depends_on    = [aws_s3_bucket_policy.access_logs]
}

resource "aws_s3_bucket_notification" "state" {
  bucket      = aws_s3_bucket.state.id
  eventbridge = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "state-history"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    id     = "access-log-retention"
    status = "Enabled"
    filter {}
    expiration {
      days = 365
    }
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  depends_on = [aws_s3_bucket_versioning.access_logs]
}

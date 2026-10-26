resource "aws_kms_key" "audit" {
  description                        = "CloudTrail archive and the project CloudWatch log group"
  deletion_window_in_days            = 30
  enable_key_rotation                = true
  bypass_policy_lockout_safety_check = false
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.key_management_statements, [
      {
        Sid       = "CloudTrailGenerateDataKeys"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:GenerateDataKey*"
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceArn" = local.trail_arn }
          StringLike   = { "kms:EncryptionContext:aws:cloudtrail:arn" = local.trail_context_arn }
        }
      },
      {
        Sid       = "CloudTrailDescribeKey"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:DescribeKey"
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
      {
        Sid       = "AdministratorReadTrailArchive"
        Effect    = "Allow"
        Principal = { AWS = local.administrator_role_arn }
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = local.s3_service }
          StringLike   = { "kms:EncryptionContext:aws:cloudtrail:arn" = local.trail_context_arn }
        }
      },
      {
        Sid       = "EncryptOnlyThisLogGroup"
        Effect    = "Allow"
        Principal = { Service = format("logs.%s.amazonaws.com", var.aws_region) }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
        Condition = { ArnEquals = { "kms:EncryptionContext:aws:logs:arn" = local.audit_log_group_arn } }
      },
      {
        Sid    = "NamedCallersThroughCloudWatchOnly"
        Effect = "Allow"
        Principal = { AWS = [
          local.administrator_role_arn,
          format("arn:aws:iam::%s:role/secure-aws-platform-%s-cloudtrail", var.expected_account_id, var.environment),
        ] }
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = format("logs.%s.amazonaws.com", var.aws_region) }
          ArnEquals    = { "kms:EncryptionContext:aws:logs:arn" = local.audit_log_group_arn }
        }
      },
    ])
  })
  depends_on = [aws_iam_role.cloudtrail]
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "audit" {
  name          = format("alias/secure-aws-platform-%s-audit", var.environment)
  target_key_id = aws_kms_key.audit.key_id
}

resource "aws_s3_bucket" "audit" {
  #checkov:skip=CKV_AWS_144:Single-region development archive; replication and immutable retention are not claimed.
  #checkov:skip=CKV2_AWS_62:Archive-object notifications are omitted to avoid a log-event feedback loop; bucket management events are monitored instead.
  bucket        = local.audit_bucket_name
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "audit" {
  bucket                  = aws_s3_bucket.audit.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule {
    # CloudTrail supplies its own encryption context. Do not enable S3 Bucket Keys here.
    bucket_key_enabled = false
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.audit.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_policy" "audit" {
  bucket = aws_s3_bucket.audit.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.audit.arn, format("%s/*", aws_s3_bucket.audit.arn)]
        Condition = { Bool = { "aws:SecureTransport" = "false", "aws:PrincipalIsAWSService" = "false" } }
      },
      {
        Sid       = "RestrictHumanAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.audit.arn, format("%s/*", aws_s3_bucket.audit.arn)]
        Condition = {
          ArnNotEquals = { "aws:PrincipalArn" = [local.administrator_role_arn, local.root_arn] }
          Bool         = { "aws:PrincipalIsAWSService" = "false" }
        }
      },
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.audit.arn
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
      {
        Sid       = "CloudTrailArchiveDelivery"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = format("%s/AWSLogs/%s/*", aws_s3_bucket.audit.arn, var.expected_account_id)
        Condition = {
          StringEquals = {
            "aws:SourceArn" = local.trail_arn
            "s3:x-amz-acl"  = "bucket-owner-full-control"
          }
        }
      },
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.audit]
}

resource "aws_s3_bucket_logging" "secure_data" {
  bucket        = aws_s3_bucket.secure_data.id
  target_bucket = local.access_logs_bucket_name
  target_prefix = "s3-access/data/"
}

resource "aws_s3_bucket_logging" "audit" {
  bucket        = aws_s3_bucket.audit.id
  target_bucket = local.access_logs_bucket_name
  target_prefix = "s3-access/audit/"
}

resource "aws_s3_bucket_notification" "secure_data" {
  bucket      = aws_s3_bucket.secure_data.id
  eventbridge = true
}

resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule {
    id     = "audit-retention"
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
  depends_on = [aws_s3_bucket_versioning.audit]
}

resource "aws_cloudwatch_log_group" "audit" {
  name              = local.audit_log_group_name
  retention_in_days = 365
  kms_key_id        = aws_kms_key.audit.arn
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role" "cloudtrail" {
  name = format("secure-aws-platform-%s-cloudtrail", var.environment)
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.expected_account_id }
        ArnEquals    = { "aws:SourceArn" = local.trail_arn }
      }
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail" {
  name = "deliver-only-project-trail"
  role = aws_iam_role.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = format("%s:log-stream:%s_CloudTrail_*", local.audit_log_group_arn, var.expected_account_id)
    }]
  })
}

resource "aws_cloudtrail" "project" {
  #checkov:skip=CKV_AWS_252:This milestone delivers security events to SQS with a delivery DLQ and visible queue alarms; external SNS notification awaits a chosen recipient.
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.audit.id
  kms_key_id                    = aws_kms_key.audit.arn
  enable_logging                = true
  enable_log_file_validation    = true
  include_global_service_events = true
  is_multi_region_trail         = true
  cloud_watch_logs_group_arn    = format("%s:*", aws_cloudwatch_log_group.audit.arn)
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail.arn

  advanced_event_selector {
    name = "Management writes"
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
    field_selector {
      field  = "readOnly"
      equals = ["false"]
    }
  }
  advanced_event_selector {
    name = "Management reads excluding high-volume KMS reads"
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
    field_selector {
      field  = "readOnly"
      equals = ["true"]
    }
    field_selector {
      field      = "eventSource"
      not_equals = ["kms.amazonaws.com"]
    }
  }
  advanced_event_selector {
    name = "Project data and state object operations"
    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }
    field_selector {
      field       = "resources.ARN"
      starts_with = [format("%s/", aws_s3_bucket.secure_data.arn), format("%s/", local.state_bucket_arn)]
    }
  }
  depends_on = [aws_s3_bucket_policy.audit, aws_iam_role_policy.cloudtrail, aws_s3_bucket_server_side_encryption_configuration.audit]
}

locals {
  root_arn                = format("arn:aws:iam::%s:root", var.expected_account_id)
  administrator_role_arn  = format("arn:aws:iam::%s:role/%s", var.expected_account_id, var.administrator_role_name)
  state_bucket_name       = format("secure-aws-platform-state-%s-%s", var.expected_account_id, var.aws_region)
  access_logs_bucket_name = format("secure-aws-platform-access-%s-%s", var.expected_account_id, var.aws_region)
  state_bucket_arn        = format("arn:aws:s3:::%s", local.state_bucket_name)
  audit_bucket_name       = format("%s-audit", local.bucket_name)
  trail_name              = format("secure-aws-platform-%s", var.environment)
  trail_arn               = format("arn:aws:cloudtrail:%s:%s:trail/%s", var.aws_region, var.expected_account_id, local.trail_name)
  trail_context_arn       = format("arn:aws:cloudtrail:*:%s:trail/%s", var.expected_account_id, local.trail_name)
  audit_log_group_name    = format("/secure-aws-platform/%s/cloudtrail", var.environment)
  audit_log_group_arn     = format("arn:aws:logs:%s:%s:log-group:%s", var.aws_region, var.expected_account_id, local.audit_log_group_name)
  s3_service              = format("s3.%s.amazonaws.com", var.aws_region)

  key_admin_actions = [
    "kms:DescribeKey", "kms:GetKeyPolicy", "kms:PutKeyPolicy",
    "kms:CreateAlias", "kms:UpdateAlias", "kms:DeleteAlias",
    "kms:ListResourceTags", "kms:TagResource", "kms:UntagResource",
    "kms:EnableKeyRotation", "kms:DisableKeyRotation", "kms:GetKeyRotationStatus",
    "kms:UpdateKeyDescription", "kms:EnableKey", "kms:DisableKey",
    "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:ListGrants", "kms:RevokeGrant",
  ]

  key_management_statements = [
    {
      Sid       = "RootRecoveryOnly"
      Effect    = "Allow"
      Principal = { AWS = local.root_arn }
      Action    = ["kms:DescribeKey", "kms:GetKeyPolicy", "kms:PutKeyPolicy"]
      Resource  = "*"
      Condition = { ArnEquals = { "aws:PrincipalArn" = local.root_arn } }
    },
    {
      Sid       = "NamedKeyAdministrator"
      Effect    = "Allow"
      Principal = { AWS = local.administrator_role_arn }
      Action    = local.key_admin_actions
      Resource  = "*"
    },
  ]

  workload_roles = {
    reader = {
      name        = format("secure-aws-platform-%s-reader", var.environment)
      s3_actions  = ["s3:GetObject", "s3:GetObjectVersion"]
      kms_actions = ["kms:Decrypt"]
    }
    writer = {
      name        = format("secure-aws-platform-%s-writer", var.environment)
      s3_actions  = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
      kms_actions = ["kms:GenerateDataKey", "kms:Decrypt"]
    }
  }
  workload_role_arns = {
    for purpose, role in local.workload_roles :
    purpose => format("arn:aws:iam::%s:role/%s", var.expected_account_id, role.name)
  }
  data_key_service_condition = {
    StringEquals = { "kms:ViaService" = local.s3_service }
    StringLike = {
      "kms:EncryptionContext:aws:s3:arn" = [
        aws_s3_bucket.secure_data.arn, format("%s/*", aws_s3_bucket.secure_data.arn),
      ]
    }
  }
}

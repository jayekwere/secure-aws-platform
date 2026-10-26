resource "aws_kms_key" "secure_data" {
  description                        = "Encrypts objects in the secure AWS platform S3 bucket"
  deletion_window_in_days            = 30
  enable_key_rotation                = true
  bypass_policy_lockout_safety_check = false

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.key_management_statements, [
      {
        Sid       = "AdministratorDataThroughS3"
        Effect    = "Allow"
        Principal = { AWS = local.administrator_role_arn }
        Action    = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource  = "*"
        Condition = local.data_key_service_condition
      },
      ], [
      for purpose, role in local.workload_roles : {
        Sid       = format("Workload%sThroughS3", title(purpose))
        Effect    = "Allow"
        Principal = { AWS = local.workload_role_arns[purpose] }
        Action    = role.kms_actions
        Resource  = "*"
        Condition = local.data_key_service_condition
      }
    ])
  })

  depends_on = [aws_iam_role.workload]

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name               = "secure-aws-platform-${var.environment}-s3"
    Purpose            = "S3 data encryption"
    DataClassification = "Internal"
  }
}

resource "aws_kms_alias" "secure_data" {
  name          = "alias/secure-aws-platform-${var.environment}-s3"
  target_key_id = aws_kms_key.secure_data.key_id
}

resource "aws_iam_role" "workload" {
  for_each             = local.workload_roles
  name                 = each.value.name
  path                 = "/"
  description          = format("Development storage %s; assumed only by the existing administrator role", each.key)
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = local.administrator_role_arn }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "workload" {
  for_each = local.workload_roles
  name     = "project-storage-only"
  role     = aws_iam_role.workload[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListWorkloadPrefixOnly"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.secure_data.arn
        Condition = {
          StringLike = { "s3:prefix" = [var.workload_prefix, format("%s*", var.workload_prefix)] }
        }
      },
      {
        Sid      = "WorkloadObjectsOnly"
        Effect   = "Allow"
        Action   = each.value.s3_actions
        Resource = format("%s/%s*", aws_s3_bucket.secure_data.arn, var.workload_prefix)
      },
      {
        Sid       = "ProjectKeyThroughS3Only"
        Effect    = "Allow"
        Action    = each.value.kms_actions
        Resource  = aws_kms_key.secure_data.arn
        Condition = local.data_key_service_condition
      },
    ]
  })
}

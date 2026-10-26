output "bucket_name" {
  description = "Name of the secure S3 bucket."
  value       = aws_s3_bucket.secure_data.bucket
}

output "bucket_arn" {
  description = "ARN of the secure S3 bucket."
  value       = aws_s3_bucket.secure_data.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the S3 bucket."
  value       = aws_kms_key.secure_data.arn
}

output "kms_alias" {
  description = "Alias of the KMS key used to encrypt the S3 bucket."
  value       = aws_kms_alias.secure_data.name
}

output "aws_region" {
  description = "AWS region used by this environment."
  value       = var.aws_region
}

output "workload_role_arns" {
  description = "Reader/writer roles limited to workloads/ by default; only the named administrator may assume them."
  value       = { for purpose, role in aws_iam_role.workload : purpose => role.arn }
}

output "audit_trail_arn" {
  description = "Multi-region trail; data-event capture is limited to the project data and state buckets."
  value       = aws_cloudtrail.project.arn
}

output "security_queue_urls" {
  description = "Poll the events queue and delivery DLQ; there is no external notification subscription."
  value       = { for purpose, queue in aws_sqs_queue.security : purpose => queue.url }
}

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

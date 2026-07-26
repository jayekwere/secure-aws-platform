output "bucket_name" {
  description = "Name of the secure S3 bucket."
  value       = aws_s3_bucket.secure_data.bucket
}

output "bucket_arn" {
  description = "ARN of the secure S3 bucket."
  value       = aws_s3_bucket.secure_data.arn
}

output "aws_region" {
  description = "AWS region used by this environment."
  value       = var.aws_region
}

output "state_backend" {
  description = "Non-secret backend settings. Do not include credentials in backend files."
  value = {
    bucket              = aws_s3_bucket.state.bucket
    key                 = "environments/dev/terraform.tfstate"
    region              = var.aws_region
    encrypt             = true
    kms_key_id          = aws_kms_key.state.arn
    use_lockfile        = true
    allowed_account_ids = [var.expected_account_id]
  }
}

output "access_logs_bucket_name" {
  description = "Shared destination for state, data, and audit-bucket server access logs."
  value       = aws_s3_bucket.access_logs.bucket
}

output "bootstrap_backend_key" {
  description = "Use this separate key if the bootstrap state is subsequently migrated to the same protected backend."
  value       = "bootstrap/terraform.tfstate"
}

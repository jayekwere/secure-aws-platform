resource "aws_s3_bucket_lifecycle_configuration" "secure_data" {
  bucket = aws_s3_bucket.secure_data.id

  rule {
    id     = "secure-data-retention"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.secure_data
  ]
}

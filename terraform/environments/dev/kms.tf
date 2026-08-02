resource "aws_kms_key" "secure_data" {
  description             = "Encrypts objects in the secure AWS platform S3 bucket"
  deletion_window_in_days = 7
  enable_key_rotation     = true

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

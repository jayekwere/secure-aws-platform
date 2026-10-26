mock_provider "aws" {
  override_during = plan

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::secure-aws-platform-dev-test"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-2:123456789012:key/00000000-0000-0000-0000-000000000001"
    }
  }
}

mock_provider "random" {
  override_during = plan
}

variables {
  expected_account_id = "123456789012"
}

run "storage_security_contract" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_public_access_block.secure_data.block_public_acls &&
      aws_s3_bucket_public_access_block.secure_data.block_public_policy &&
      aws_s3_bucket_public_access_block.secure_data.ignore_public_acls &&
      aws_s3_bucket_public_access_block.secure_data.restrict_public_buckets
    )
    error_message = "All four public access protections must remain enabled."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.secure_data.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "ACL-based access control must remain disabled."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.secure_data.versioning_configuration).status == "Enabled"
    error_message = "Object versioning must remain enabled."
  }

  assert {
    condition = (
      one(aws_s3_bucket_server_side_encryption_configuration.secure_data.rule).bucket_key_enabled &&
      one(one(aws_s3_bucket_server_side_encryption_configuration.secure_data.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms" &&
      one(one(aws_s3_bucket_server_side_encryption_configuration.secure_data.rule).apply_server_side_encryption_by_default).kms_master_key_id == aws_kms_key.secure_data.arn &&
      aws_kms_key.secure_data.enable_key_rotation
    )
    error_message = "Default encryption must use the rotating project KMS key and a Bucket Key."
  }

  assert {
    condition     = !aws_s3_bucket.secure_data.force_destroy
    error_message = "Deleting bucket contents must require an explicit teardown opt-in."
  }

  assert {
    condition = (
      aws_s3_bucket_policy.secure_data.bucket == aws_s3_bucket.secure_data.id &&
      jsondecode(aws_s3_bucket_policy.secure_data.policy).Version == "2012-10-17" &&
      length(jsondecode(aws_s3_bucket_policy.secure_data.policy).Statement) == 3 &&
      alltrue([
        for statement in jsondecode(aws_s3_bucket_policy.secure_data.policy).Statement :
        statement.Effect == "Deny" && statement.Principal == "*"
      ])
    )
    error_message = "The bucket policy must attach to this bucket and contain only the three universal denies."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.secure_data.policy).Statement :
      try(
        statement.Sid == "DenyInsecureTransport" &&
        statement.Action == "s3:*" &&
        toset(statement.Resource) == toset([aws_s3_bucket.secure_data.arn, "${aws_s3_bucket.secure_data.arn}/*"]) &&
        statement.Condition == { Bool = { "aws:SecureTransport" = "false", "aws:PrincipalIsAWSService" = "false" } },
        false
      )
    ])
    error_message = "The policy must deny non-service HTTP requests on the bucket and all objects."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.secure_data.policy).Statement :
      try(
        statement.Sid == "DenyUnexpectedEncryption" &&
        statement.Action == "s3:PutObject" &&
        statement.Resource == "${aws_s3_bucket.secure_data.arn}/*" &&
        statement.Condition == { StringNotEquals = { "s3:x-amz-server-side-encryption" = "aws:kms" } },
        false
      )
    ])
    error_message = "Uploads must explicitly request aws:kms encryption."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.secure_data.policy).Statement :
      try(
        statement.Sid == "DenyUnexpectedKmsKey" &&
        statement.Action == "s3:PutObject" &&
        statement.Resource == "${aws_s3_bucket.secure_data.arn}/*" &&
        statement.Condition == { StringNotEquals = { "s3:x-amz-server-side-encryption-aws-kms-key-id" = aws_kms_key.secure_data.arn } },
        false
      )
    ])
    error_message = "The upload policy must be restricted to the project KMS key ARN."
  }
}

mock_provider "aws" {
  override_during = plan
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-2:123456789012:key/00000000-0000-0000-0000-000000000002" }
  }
}
override_resource {
  override_during = plan
  target          = aws_s3_bucket.state
  values          = { arn = "arn:aws:s3:::secure-aws-platform-state-123456789012-us-east-2" }
}
override_resource {
  override_during = plan
  target          = aws_s3_bucket.access_logs
  values          = { arn = "arn:aws:s3:::secure-aws-platform-access-123456789012-us-east-2" }
}
variables {
  expected_account_id = "123456789012"
  data_bucket_name    = "secure-aws-platform-dev-1234abcd"
}

run "protected_backend_contract" {
  command = plan
  assert {
    condition = alltrue([for action in ["kms:CreateAlias", "kms:UpdateAlias", "kms:DeleteAlias"] :
      contains(jsondecode(aws_kms_key.state.policy).Statement[1].Action, action)
    ])
    error_message = "The named state key administrator must be able to manage aliases."
  }
  assert {
    condition = (alltrue([for controls in [aws_s3_bucket_public_access_block.state, aws_s3_bucket_public_access_block.access_logs] :
      controls.block_public_acls && controls.block_public_policy && controls.ignore_public_acls && controls.restrict_public_buckets
      ]) && alltrue([for bucket in [aws_s3_bucket.state, aws_s3_bucket.access_logs] : !bucket.force_destroy]) &&
    alltrue([for resource in [aws_s3_bucket_versioning.state, aws_s3_bucket_versioning.access_logs] : one(resource.versioning_configuration).status == "Enabled"]))
    error_message = "Both foundation buckets must block public access, retain versions and forbid forced cleanup."
  }
  assert {
    condition = (
      one(one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default).kms_master_key_id == aws_kms_key.state.arn &&
      one(one(aws_s3_bucket_server_side_encryption_configuration.access_logs.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256" &&
      aws_kms_key.state.enable_key_rotation && aws_kms_key.state.deletion_window_in_days == 30 &&
      !aws_kms_key.state.bypass_policy_lockout_safety_check &&
      jsondecode(aws_kms_key.state.policy).Statement[0].Condition.ArnEquals["aws:PrincipalArn"] == "arn:aws:iam::123456789012:root" &&
      jsondecode(aws_kms_key.state.policy).Statement[2].Condition.StringEquals["kms:ViaService"] == "s3.us-east-2.amazonaws.com"
    )
    error_message = "State needs a rotating scoped CMK; S3 access-log delivery needs its separate SSE-S3 sink."
  }
  assert {
    condition = (
      output.state_backend.encrypt && output.state_backend.use_lockfile &&
      output.state_backend.kms_key_id == aws_kms_key.state.arn &&
      output.state_backend.allowed_account_ids == ["123456789012"] &&
      jsondecode(aws_s3_bucket_policy.state.policy).Statement[1].Condition.ArnNotEquals["aws:PrincipalArn"] == ["arn:aws:iam::123456789012:role/CloudAdministratorRole", "arn:aws:iam::123456789012:root"] &&
      jsondecode(aws_s3_bucket_policy.state.policy).Statement[3].Condition.StringNotEquals["s3:x-amz-server-side-encryption-aws-kms-key-id"] == aws_kms_key.state.arn
    )
    error_message = "The proposed backend must use native locking, the state key and an explicit account/access boundary."
  }
  assert {
    condition = (
      toset(jsondecode(aws_s3_bucket_policy.state.policy).Statement[4].Action) == toset(["s3:DeleteObject", "s3:DeleteObjectVersion"]) &&
      toset(jsondecode(aws_s3_bucket_policy.state.policy).Statement[4].Resource) == toset([
        "arn:aws:s3:::secure-aws-platform-state-123456789012-us-east-2/environments/dev/terraform.tfstate",
        "arn:aws:s3:::secure-aws-platform-state-123456789012-us-east-2/bootstrap/terraform.tfstate",
      ]) &&
      alltrue([for rule in aws_s3_bucket_lifecycle_configuration.state.rule : length(rule.expiration) == 0])
    )
    error_message = "State deletion must be denied on exact state keys, never on .tflock, with no current-state expiry."
  }
  assert {
    condition = (
      aws_s3_bucket_notification.state.eventbridge &&
      aws_s3_bucket_logging.state.target_bucket == aws_s3_bucket.access_logs.id &&
      jsondecode(aws_s3_bucket_policy.access_logs.policy).Statement[2].Principal.Service == "logging.s3.amazonaws.com" &&
      jsondecode(aws_s3_bucket_policy.access_logs.policy).Statement[2].Condition.StringEquals["aws:SourceAccount"] == "123456789012" &&
      toset(jsondecode(aws_s3_bucket_policy.access_logs.policy).Statement[2].Condition.ArnLike["aws:SourceArn"]) == toset([
        "arn:aws:s3:::secure-aws-platform-state-123456789012-us-east-2",
        "arn:aws:s3:::secure-aws-platform-dev-1234abcd",
        "arn:aws:s3:::secure-aws-platform-dev-1234abcd-audit",
      ])
    )
    error_message = "Log delivery must be limited to the three project buckets in this account."
  }
}

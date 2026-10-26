mock_provider "aws" {
  override_during = plan
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::secure-aws-platform-dev-1234abcd" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-2:123456789012:key/00000000-0000-0000-0000-000000000001" }
  }
}
mock_provider "random" {
  override_during = plan
  mock_resource "random_id" {
    defaults = { hex = "1234abcd" }
  }
}
override_resource {
  override_during = plan
  target          = aws_s3_bucket.audit
  values          = { arn = "arn:aws:s3:::secure-aws-platform-dev-1234abcd-audit" }
}
variables {
  expected_account_id = "123456789012"
}

run "access_audit_detection_contract" {
  command = plan
  assert {
    condition = alltrue([for policy in [aws_kms_key.secure_data.policy, aws_kms_key.audit.policy] :
      alltrue([for action in ["kms:CreateAlias", "kms:UpdateAlias", "kms:DeleteAlias"] :
        contains(jsondecode(policy).Statement[1].Action, action)
      ])
    ])
    error_message = "Named key administrators must be able to manage aliases without broad cryptographic access."
  }
  assert {
    condition = (
      jsondecode(aws_iam_role.workload["reader"].assume_role_policy).Statement == [{
        Effect = "Allow", Principal = { AWS = "arn:aws:iam::123456789012:role/CloudAdministratorRole" }, Action = "sts:AssumeRole"
      }] && aws_iam_role.workload["reader"].max_session_duration == 3600 &&
      jsondecode(aws_iam_role.workload["writer"].assume_role_policy).Statement == [{
        Effect = "Allow", Principal = { AWS = "arn:aws:iam::123456789012:role/CloudAdministratorRole" }, Action = "sts:AssumeRole"
      }] && aws_iam_role.workload["writer"].max_session_duration == 3600
    )
    error_message = "Both workload roles must trust only the named administrator for bounded sessions."
  }
  assert {
    condition = (
      toset(jsondecode(aws_iam_role_policy.workload["reader"].policy).Statement[1].Action) == toset(["s3:GetObject", "s3:GetObjectVersion"]) &&
      toset(jsondecode(aws_iam_role_policy.workload["writer"].policy).Statement[1].Action) == toset(["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]) &&
      alltrue([for policy in aws_iam_role_policy.workload :
        jsondecode(policy.policy).Statement[1].Resource == "arn:aws:s3:::secure-aws-platform-dev-1234abcd/workloads/*" &&
        jsondecode(policy.policy).Statement[0].Condition.StringLike["s3:prefix"] == ["workloads/", "workloads/*"]
      ])
    )
    error_message = "Reader and writer permissions must remain separate and restricted to workloads/."
  }
  assert {
    condition = alltrue([for key in [aws_kms_key.secure_data, aws_kms_key.audit] :
      key.enable_key_rotation && key.deletion_window_in_days == 30 && !key.bypass_policy_lockout_safety_check &&
      jsondecode(key.policy).Statement[0].Action == ["kms:DescribeKey", "kms:GetKeyPolicy", "kms:PutKeyPolicy"] &&
      jsondecode(key.policy).Statement[0].Condition.ArnEquals["aws:PrincipalArn"] == "arn:aws:iam::123456789012:root" &&
      !contains(jsondecode(key.policy).Statement[1].Action, "kms:*") &&
      contains(jsondecode(key.policy).Statement[1].Action, "kms:PutKeyPolicy")
    ])
    error_message = "Keys must retain named administration, root-only recovery, rotation and lockout protection."
  }
  assert {
    condition = (
      jsondecode(aws_kms_key.secure_data.policy).Statement[3].Action == ["kms:Decrypt"] &&
      toset(jsondecode(aws_kms_key.secure_data.policy).Statement[4].Action) == toset(["kms:GenerateDataKey", "kms:Decrypt"]) &&
      alltrue([for statement in slice(jsondecode(aws_kms_key.secure_data.policy).Statement, 2, 5) :
        statement.Condition.StringEquals["kms:ViaService"] == "s3.us-east-2.amazonaws.com" &&
        toset(statement.Condition.StringLike["kms:EncryptionContext:aws:s3:arn"]) == toset(["arn:aws:s3:::secure-aws-platform-dev-1234abcd", "arn:aws:s3:::secure-aws-platform-dev-1234abcd/*"])
      ])
    )
    error_message = "Data cryptography must be purpose-specific and limited to S3 with this bucket context."
  }
  assert {
    condition = (
      aws_cloudtrail.project.enable_logging && aws_cloudtrail.project.enable_log_file_validation &&
      aws_cloudtrail.project.is_multi_region_trail && aws_cloudtrail.project.include_global_service_events &&
      aws_cloudtrail.project.kms_key_id == aws_kms_key.audit.arn &&
      aws_cloudwatch_log_group.audit.kms_key_id == aws_kms_key.audit.arn &&
      aws_cloudwatch_log_group.audit.retention_in_days == 365 &&
      aws_cloudtrail.project.cloud_watch_logs_role_arn == aws_iam_role.cloudtrail.arn
    )
    error_message = "The trail must be enabled, validated, multi-region and delivered to encrypted S3 and CloudWatch."
  }
  assert {
    condition = anytrue([for selector in aws_cloudtrail.project.advanced_event_selector :
      selector.name == "Project data and state object operations" && anytrue([for field in selector.field_selector :
        field.field == "resources.ARN" && toset(field.starts_with) == toset([
          "arn:aws:s3:::secure-aws-platform-dev-1234abcd/", "arn:aws:s3:::secure-aws-platform-state-123456789012-us-east-2/"
        ])
      ])
    ])
    error_message = "Data events must include only data/state objects, excluding log destinations to avoid recursion."
  }
  assert {
    condition = (
      jsondecode(aws_kms_key.audit.policy).Statement[2].Condition.StringEquals["aws:SourceArn"] == "arn:aws:cloudtrail:us-east-2:123456789012:trail/secure-aws-platform-dev" &&
      jsondecode(aws_kms_key.audit.policy).Statement[5].Condition.ArnEquals["kms:EncryptionContext:aws:logs:arn"] == "arn:aws:logs:us-east-2:123456789012:log-group:/secure-aws-platform/dev/cloudtrail" &&
      jsondecode(aws_kms_key.audit.policy).Statement[6].Condition.StringEquals["kms:ViaService"] == "logs.us-east-2.amazonaws.com" &&
      toset(jsondecode(aws_kms_key.audit.policy).Statement[6].Principal.AWS) == toset([
        "arn:aws:iam::123456789012:role/CloudAdministratorRole", "arn:aws:iam::123456789012:role/secure-aws-platform-dev-cloudtrail"
      ]) &&
      jsondecode(aws_s3_bucket_policy.audit.policy).Statement[3].Condition.StringEquals["aws:SourceArn"] == "arn:aws:cloudtrail:us-east-2:123456789012:trail/secure-aws-platform-dev" &&
      jsondecode(aws_iam_role.cloudtrail.assume_role_policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == "arn:aws:cloudtrail:us-east-2:123456789012:trail/secure-aws-platform-dev" &&
      jsondecode(aws_iam_role_policy.cloudtrail.policy).Statement[0].Resource == "arn:aws:logs:us-east-2:123456789012:log-group:/secure-aws-platform/dev/cloudtrail:log-stream:123456789012_CloudTrail_*"
    )
    error_message = "Service delivery must be scoped to the exact trail, log group and permitted log streams."
  }
  assert {
    condition = (
      aws_s3_bucket_notification.secure_data.eventbridge &&
      aws_s3_bucket_logging.secure_data.target_bucket == "secure-aws-platform-access-123456789012-us-east-2" &&
      aws_s3_bucket_logging.audit.target_bucket == aws_s3_bucket_logging.secure_data.target_bucket &&
      !one(aws_s3_bucket_server_side_encryption_configuration.audit.rule).bucket_key_enabled &&
      aws_s3_bucket_public_access_block.audit.block_public_acls && aws_s3_bucket_public_access_block.audit.block_public_policy &&
      aws_s3_bucket_public_access_block.audit.ignore_public_acls && aws_s3_bucket_public_access_block.audit.restrict_public_buckets &&
      one(aws_s3_bucket_versioning.audit.versioning_configuration).status == "Enabled"
    )
    error_message = "Storage logging and notifications must use the separate protected log destination."
  }
  assert {
    condition = alltrue([for policy in [aws_sqs_queue_policy.security["events"].policy, aws_sqs_queue_policy.security["delivery-dlq"].policy] :
      jsondecode(policy).Statement[1].Principal.Service == "events.amazonaws.com" &&
      jsondecode(policy).Statement[1].Action == "sqs:SendMessage" &&
      jsondecode(policy).Statement[1].Condition.StringEquals["aws:SourceAccount"] == "123456789012" &&
      toset(jsondecode(policy).Statement[1].Condition.ArnEquals["aws:SourceArn"]) == toset([
        aws_cloudwatch_event_rule.security["bucket_controls"].arn,
        aws_cloudwatch_event_rule.security["key_controls"].arn,
        aws_cloudwatch_event_rule.security["object_deletion"].arn,
        aws_cloudwatch_event_rule.security["audit_controls"].arn,
      ])
    ])
    error_message = "Only the project rules may send events, scoped to this account."
  }
  assert {
    condition = alltrue([for target in aws_cloudwatch_event_target.security :
      target.arn == aws_sqs_queue.security["events"].arn &&
      one(target.dead_letter_config).arn == aws_sqs_queue.security["delivery-dlq"].arn
    ])
    error_message = "Every rule must deliver to the security queue with a separate delivery-failure queue."
  }
  assert {
    condition = (
      alltrue([for queue in aws_sqs_queue.security : queue.sqs_managed_sse_enabled && queue.message_retention_seconds == 1209600]) &&
      alltrue([for alarm in aws_cloudwatch_metric_alarm.security_queue :
        alarm.metric_name == "ApproximateNumberOfMessagesVisible" && alarm.threshold == 0 && length(coalesce(alarm.alarm_actions, [])) == 0
      ]) &&
      length(aws_cloudwatch_event_rule.security) == 4
    )
    error_message = "Events and delivery failures need encrypted retention and visible alarms; no external pager is claimed."
  }
}

override_resource {
  override_during = plan
  target          = aws_iam_role.cloudtrail
  values          = { arn = "arn:aws:iam::123456789012:role/secure-aws-platform-dev-cloudtrail", id = "secure-aws-platform-dev-cloudtrail" }
}

override_resource {
  override_during = plan
  target          = aws_kms_key.audit
  values          = { arn = "arn:aws:kms:us-east-2:123456789012:key/00000000-0000-0000-0000-000000000002" }
}

override_resource {
  override_during = plan
  target          = aws_sqs_queue.security["events"]
  values          = { arn = "arn:aws:sqs:us-east-2:123456789012:secure-aws-platform-dev-events" }
}

override_resource {
  override_during = plan
  target          = aws_sqs_queue.security["delivery-dlq"]
  values          = { arn = "arn:aws:sqs:us-east-2:123456789012:secure-aws-platform-dev-delivery-dlq" }
}

override_resource {
  override_during = plan
  target          = aws_cloudwatch_event_rule.security["bucket_controls"]
  values          = { arn = "arn:aws:events:us-east-2:123456789012:rule/secure-aws-platform-dev-bucket-controls" }
}

override_resource {
  override_during = plan
  target          = aws_cloudwatch_event_rule.security["key_controls"]
  values          = { arn = "arn:aws:events:us-east-2:123456789012:rule/secure-aws-platform-dev-key-controls" }
}

override_resource {
  override_during = plan
  target          = aws_cloudwatch_event_rule.security["object_deletion"]
  values          = { arn = "arn:aws:events:us-east-2:123456789012:rule/secure-aws-platform-dev-object-deletion" }
}

override_resource {
  override_during = plan
  target          = aws_cloudwatch_event_rule.security["audit_controls"]
  values          = { arn = "arn:aws:events:us-east-2:123456789012:rule/secure-aws-platform-dev-audit-controls" }
}

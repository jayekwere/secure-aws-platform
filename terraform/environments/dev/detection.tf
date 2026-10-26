locals {
  security_event_patterns = {
    bucket_controls = {
      source        = ["aws.s3"]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail = {
        eventSource = ["s3.amazonaws.com"]
        eventName = [
          "PutBucketPolicy", "DeleteBucketPolicy", "PutBucketPublicAccessBlock", "DeleteBucketPublicAccessBlock",
          "PutBucketEncryption", "DeleteBucketEncryption", "PutBucketVersioning", "PutBucketLogging", "PutBucketNotification",
        ]
        requestParameters = { bucketName = [local.bucket_name, local.audit_bucket_name, local.state_bucket_name, local.access_logs_bucket_name] }
      }
    }
    key_controls = {
      source        = ["aws.kms"]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail = {
        eventSource = ["kms.amazonaws.com"]
        eventName   = ["PutKeyPolicy", "DisableKey", "ScheduleKeyDeletion", "DisableKeyRotation"]
      }
    }
    object_deletion = {
      source        = ["aws.s3"]
      "detail-type" = ["Object Deleted"]
      detail = {
        "$or" = [
          { bucket = { name = [local.bucket_name] }, object = { key = [{ prefix = var.workload_prefix }] } },
          { bucket = { name = [local.state_bucket_name] }, object = { key = ["environments/dev/terraform.tfstate", "bootstrap/terraform.tfstate"] } },
        ]
      }
    }
    audit_controls = {
      source        = ["aws.cloudtrail"]
      "detail-type" = ["AWS API Call via CloudTrail"]
      detail = {
        eventSource       = ["cloudtrail.amazonaws.com"]
        eventName         = ["StopLogging", "DeleteTrail", "UpdateTrail", "PutEventSelectors"]
        requestParameters = { name = [local.trail_name, local.trail_arn] }
      }
    }
  }
}

resource "aws_sqs_queue" "security" {
  for_each                   = toset(["events", "delivery-dlq"])
  name                       = format("secure-aws-platform-%s-%s", var.environment, each.key)
  sqs_managed_sse_enabled    = true
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 60
}

resource "aws_cloudwatch_event_rule" "security" {
  for_each      = local.security_event_patterns
  name          = format("secure-aws-platform-%s-%s", var.environment, replace(each.key, "_", "-"))
  description   = "Capture project security changes for operator review; no automatic remediation"
  event_pattern = jsonencode(each.value)
  state         = "ENABLED"
}

resource "aws_sqs_queue_policy" "security" {
  for_each  = aws_sqs_queue.security
  queue_url = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = each.value.arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "ProjectEventRulesOnly"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = each.value.arn
        Condition = {
          ArnEquals    = { "aws:SourceArn" = [for rule in aws_cloudwatch_event_rule.security : rule.arn] }
          StringEquals = { "aws:SourceAccount" = var.expected_account_id }
        }
      },
    ]
  })
}

resource "aws_cloudwatch_event_target" "security" {
  for_each  = aws_cloudwatch_event_rule.security
  rule      = each.value.name
  target_id = "security-review-queue"
  arn       = aws_sqs_queue.security["events"].arn
  dead_letter_config {
    arn = aws_sqs_queue.security["delivery-dlq"].arn
  }
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 185
  }
  depends_on = [aws_sqs_queue_policy.security]
}

resource "aws_cloudwatch_metric_alarm" "security_queue" {
  for_each            = aws_sqs_queue.security
  alarm_name          = format("secure-aws-platform-%s-%s-pending", var.environment, each.key)
  alarm_description   = "Security messages require operator review in SQS. No external notification is configured."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = each.value.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

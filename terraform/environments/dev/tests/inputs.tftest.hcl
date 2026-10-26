mock_provider "aws" {
  override_during = plan
}

mock_provider "random" {
  override_during = plan
}

variables {
  expected_account_id = "123456789012"
}

run "reject_production_label" {
  command = plan
  variables {
    environment = "prod"
  }
  expect_failures = [var.environment]
}

run "reject_malformed_account" {
  command = plan
  variables {
    expected_account_id = "not-an-account"
  }
  expect_failures = [var.expected_account_id]
}

run "explicit_teardown_opt_in" {
  command = plan
  variables {
    allow_force_destroy = true
  }
  assert {
    condition     = aws_s3_bucket.secure_data.force_destroy
    error_message = "Explicit teardown opt-in must remain available for disposable lab data."
  }
}

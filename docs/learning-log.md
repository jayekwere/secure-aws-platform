# Learning Log

This document records what was built, what was learned, and what security decisions were made during the project.

## 2026-07-26 — Project Initialization

### Completed

- Created the public `secure-aws-platform` GitHub repository.
- Cloned the repository to the local Mac.
- Confirmed Git installation.
- Installed Terraform.
- Installed GitHub CLI.
- Authenticated GitHub CLI as `jayekwere`.
- Installed AWS CLI version 2.
- Confirmed Docker CLI installation.
- Added the initial project README.
- Added repository protections through `.gitignore`.

### Key Security Lesson

Credentials, Terraform state files, private keys, and environment files must not be committed to source control.

### Next Phase

Prepare the Git repository workflow and secure the AWS account before deploying infrastructure.

## 2026-07-26 — First Terraform AWS Deployment

### Completed

- Created the `feat/terraform-s3-foundation` feature branch.
- Configured the AWS and Random Terraform providers.
- Added validated environment and AWS region variables.
- Generated a globally unique S3 bucket name.
- Enabled all S3 public-access-block controls.
- Disabled ACL-based object ownership.
- Enabled object versioning.
- Enabled S3-managed server-side encryption.
- Reviewed and applied a saved Terraform execution plan.
- Verified the deployed controls through the AWS CLI.
- Confirmed Terraform idempotency with a no-change plan.

### Terraform Concepts Learned

- Providers connect Terraform to external platforms.
- Resources represent infrastructure objects.
- Variables accept reusable input values.
- Locals create reusable expressions inside a configuration.
- Outputs expose selected deployment information.
- State maps Terraform resource addresses to real infrastructure.
- Saved plans allow reviewed changes to be applied exactly.
- Idempotency means repeated execution produces no unnecessary changes.

### Security Lesson

Writing a secure infrastructure definition is only one part of validation. Security controls should also be verified against the live cloud environment after deployment.

### Next Phase

Add automated Terraform formatting, validation, linting, and security scanning through CI/CD.

## 2026-08-02 — Checkov Findings Remediation

### Completed

- Reviewed five Checkov findings and classified them by risk and applicability.
- Upgraded the S3 bucket from SSE-S3 to SSE-KMS.
- Created a customer-managed KMS key with automatic rotation.
- Enabled an S3 Bucket Key.
- Added lifecycle controls for incomplete uploads and noncurrent versions.
- Added documented resource-scoped suppressions for deferred controls.
- Updated the existing bucket without replacing or destroying it.
- Confirmed Terraform idempotency after deployment.

### Security Lesson

A successful scanner job does not necessarily mean zero findings when audit or soft-fail mode is enabled. Findings must be reviewed, prioritized, remediated, deferred with justification, or rejected as not applicable.

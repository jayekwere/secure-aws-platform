# Learning Log

This document records what was built, what was learned, and what security decisions were made during the project.

Entries describe work reported at the time, not a current inventory of deployed AWS resources. Raw AWS verification output is not retained here. See the [README](../README.md#verification-results) for current scope and the limits of the available evidence.

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
- Added `.gitignore` rules for state, plans, and common credential files.

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

## 2026-08-22 — Blocking Static Scan and KMS Policy Deferral

### Completed

- Changed Checkov from soft-fail to blocking mode for unsuppressed findings ([commit](https://github.com/jayekwere/secure-aws-platform/commit/fc7fc6d85331e7e90eed36ebddaffdbd7cd04616)).
- Added a resource-scoped suppression for the missing explicit KMS key policy ([commit](https://github.com/jayekwere/secure-aws-platform/commit/cc556d9b410b403050a11812ffc19e1f97cea260)).
- Documented that key authorization still relies on the AWS default policy and externally managed IAM.

### Security Lesson

A blocking scanner still permits explicitly suppressed findings. A documented deferral records a gap; it does not implement the missing control or establish an expiry process.

## 2026-10-25 — Scope and Presentation Review

### Completed

- Reframed the README around the implemented S3/KMS development foundation.
- Separated Terraform-defined controls, historical deployment reports, static validation results, and planned work.
- Documented destructive lab defaults, external identity assumptions, missing policy boundaries, local state, and validation limits.
- Added a read-only AWS verification procedure without claiming it was run against the account.
- Prepared a local repository-description draft and project walkthrough.

### Security Lesson

Default encryption, static validation, and a historical no-change plan answer different questions. Authorization and detection claims need their own executable evidence. The October review did not establish the current AWS deployment state.

### Next Milestone

Implement and test the S3/KMS access boundary, then add protected state and one observable detection and restoration scenario. No Terraform, workflow, or GitHub settings were changed by this documentation update.

## 2026-10-25 — Local Storage Policy Milestone

### Implemented Locally, Pending Deployment

- Added a deny-only bucket policy for non-service HTTP requests and uploads missing explicit SSE-KMS/project-key headers.
- Required an expected AWS account ID, restricted the root module to development, and made destructive cleanup an explicit opt-in.
- Added four mocked Terraform plan tests and seven deliberate source mutations; all passed their expected outcomes locally.
- Configured the workflow to run the regression checks; it has not run in hosted CI.
- Recorded source hashes and sanitized local results in the [verification evidence](evidence/storage-policy-tests-local.json).

### Read-Only Console Inspection

The existing `CloudAdministratorRole` allowed inspection of the original Ohio development bucket after the signed-in IAM user's bucket listing was denied. Public access blocking, ownership, versioning, SSE-KMS, the Bucket Key, and selected lifecycle/notification settings were observed. See the [exact scope and limitations](storage-policy-contract.md#read-only-console-observations).

No AWS resources were changed. The original Terraform state is absent from this checkout, so the new local configuration was not applied.

### Next Step

Recover and reconcile the original state or prepare a reviewed import plan, then inspect a scoped update plan before deploying the policy and testing real allowed/denied requests.

## 2026-10-26 — Applied Storage Guardrails and Live Verification

### Completed

- Recovered the original serial-12 state and matched its bucket/key identifiers against AWS using the existing role.
- Applied the reviewed plan to the existing resources: one policy added, one bucket-management setting changed, no replacements or deletions.
- Made the recovered state in this checkout authoritative at serial 15. The original checkout's state remains an unchanged pre-apply archive.
- Passed 20 verification checks, including correct-key and multipart uploads, encrypted download, anonymous-read denial, missing-header/SSE-S3/different-existing-key denials, and real wrong-account rejection.
- Removed all four synthetic object versions created across the verification probes.
- Confirmed a final Terraform plan with no changes.
- Rechecked the local mocked tests, seven deliberate regressions, TFLint, and Checkov. Hosted CI remains unrun because nothing was pushed.

### Observed AWS Behavior

A nonexistent-key probe returned `KMS.NotFoundException` before policy authorization, so it was not counted as proof of policy denial. A valid alias resolving to the approved key succeeded; the documentation and assertion wording now reflect resolved-key enforcement rather than literal ARN-only client syntax. A different existing key was explicitly denied.

### Remaining Scope

This completes the reviewed storage-policy milestone. Explicit workload IAM and KMS key policies, centralized logging/detection, and remote state with recovery remain separate work. The current role is an administrator; these checks do not establish workload least privilege or account-wide security coverage.


## 2026-10-26 — Deployed Access, Audit, Detection and Remote State

- Applied the authorized foundation and development plans: 52 resources created, the existing data key preserved and updated, no replacement/deletion. A missing alias-administration permission caused a partial bootstrap failure; a narrow key-administration repair completed it. Both roots now have negative regression tests for that omission.
- Passed 56 live control/delivery checks, including role boundaries, direct-KMS denials, multipart operations, actual encrypted archive/CloudWatch delivery, a real event in SQS and an alarm reaching ALARM. Synthetic data versions were removed; security queue messages were retained.
- Migrated both Terraform roots into their protected S3 backend and passed 16 backend checks. Real plans demonstrated encrypted native lock contention and normal lock release. Previous real state versions were retrieved privately, without restoring over active state. Both final provider-backed plans showed no changes.
- Migration created new remote lineage IDs and serial sequences. Exact resource inventories and outputs were preserved; old local states are private archives, and remote state is authoritative.
- Excluded malformed nonexistent-version probes from deny evidence because S3 rejected their syntax before authorization. The bootstrap state deletion restriction was checked in the live policy; no real state version was deleted.
- Passed six mocked plan runs, all 18 deliberate regressions, both lint roots and the final Checkov scan (123 passed, 0 failed, 9 explicit exceptions). Source-bound evidence is retained under `docs/evidence/phase2-*`.
- Hosted CI [passed all five jobs](https://github.com/jayekwere/secure-aws-platform/actions/runs/40346124360) for `bb56adf` after adding HashiCorp-verified Linux provider checksums; provider versions and resource configuration did not change. External paging, budget alerts, immutable workflow dependencies, required reviews and a full restoration exercise remain follow-up work. This is a scoped development lab.


## 2026-10-26 — Foundation Handover and Free Alert Setup

- Tested the exact backend-reconstruction snippet from a fresh temporary checkout. Both roots attached to existing state without migration and produced no-change AWS plans. The temporary checkout was removed.
- Added an operations guide covering temporary authentication, private backend reconstruction, future increments, monitoring, recovery and teardown boundaries.
- Added a free actual-cost warning above US$0.01 to an existing account budget, preserving its limit and other alerts. No paid budget report/action was created; the warning is not a spending cap.
- Configured free account-level AWS User Notifications for only the two project queue alarms in the deployment region, without another customer-managed key or SNS topic. Email activation and receipt are separate verification steps, tracked in the evidence record.
- Kept personal notification addresses and account-specific configuration private. The AWS account remained on its active Free plan after setup; no paid-plan upgrade was performed.
- Updated two alarm descriptions to reflect the separate account-level routing and obtained a no-change development plan. No additional Terraform resources were created.

The [closeout hosted run](https://github.com/jayekwere/secure-aws-platform/actions/runs/40389220930) passed all five jobs, six plan runs and 18 deliberate regressions for `5fda09e`.

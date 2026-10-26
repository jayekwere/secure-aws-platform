# Project Presentation

Draft for the repository's About fields and a short walkthrough. Editing this file does not update GitHub settings.

## Proposed repository description

Terraform AWS security lab with enforced S3/KMS storage controls, bounded IAM, encrypted audit logging, event detection, protected state and GitHub Actions security checks.

## Proposed topics

`terraform`, `aws`, `amazon-s3`, `aws-kms`, `cloud-security`, `infrastructure-as-code`, `github-actions`

## Short introduction

Secure AWS Platform currently implements a single-region S3/KMS development foundation in Terraform. It defines public access blocking, bucket-owner-enforced ownership, versioning, default customer-managed KMS encryption with rotation, and storage lifecycle rules. GitHub Actions checks formatting, validates the configuration, runs TFLint, and blocks unsuppressed Checkov findings. The deployed milestone adds restricted reader/writer access, explicit key policies, encrypted audit logging, security-event capture and protected remote state. Live evidence distinguishes successful requests and observed event delivery from configured protections.

The [deployed storage milestone](storage-policy-contract.md) adds a deny-only request policy, account/development safeguards, and regression tests. Its reviewed plan was applied to the existing bucket, 20 verification checks passed, and the final plan showed no changes. The [deployed access/audit/state milestone](phase-2-access-audit-state.md) passes six mocked plan runs, 18 deliberate regression checks and 15 EventBridge pattern checks. The live records cover role authorization, encrypted log/event delivery and state-backend verification. [Hosted CI](https://github.com/jayekwere/secure-aws-platform/actions/runs/40346124360) passed all five jobs for `bb56adf`.

## Five-minute walkthrough

1. **Start with scope.** Open the [README](../README.md). Show the deployed foundation, the deployed access/audit/state milestone and the remaining work as separate statuses.
2. **Inspect storage controls.** Open [main.tf](../terraform/environments/dev/main.tf). Show the four public-access-block settings, disabled ACLs, and versioning. Distinguish the deployed bucket policy from the deployed IAM roles and explicit KMS policy.
3. **Explain encryption and retention.** Open [kms.tf](../terraform/environments/dev/kms.tf) and [lifecycle.tf](../terraform/environments/dev/lifecycle.tf). Distinguish default encryption from required-key enforcement, and versioning from immutable retention. Show how the explicit policy replaces default IAM delegation with named key administration and encryption through S3; explain retained administrator/root recovery access.
4. **Show the available evidence.** Start with the [20 live storage checks](evidence/storage-live-verification.json), then the current milestone's [local evidence and limits](phase-2-access-audit-state.md#local-verification-and-limits). Explain the nine current scanner exceptions. The [recorded hosted CI run](https://github.com/jayekwere/secure-aws-platform/actions/runs/40050245606) is historical; current publication evidence is separate.
5. **Close with the next verifiable outcome.** Show the [next steps](../README.md#next-steps): email verification/receipt, ongoing cost review, stronger CI enforcement and a detection-to-restoration exercise.

## Boundaries to state alongside the demonstration

- Historical deployment notes and the later read-only console inspection have different evidence limits. The console inspection found the original bucket and checked selected settings; it did not prove authorization or full state reconciliation.
- The bucket policy is applied and verified with synthetic uploads, downloads, denials, and multipart requests. Workload roles, explicit KMS policies, logging/detection and the state foundation are deployed. Read the live records for the exact tested boundaries; account-level email routing and an early cost warning have separate setup/verification records; automatic remediation and full account-wide coverage are not implemented. Private networking, OIDC deployment and application workloads remain future work.
- Containers, EKS, Kubernetes policies, and admission control are longer-term possibilities. They are not current project capabilities.
- The local development configuration now rejects production labels and requires explicit opt-in for destructive bucket cleanup. It remains a disposable lab.

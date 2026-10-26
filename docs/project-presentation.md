# Project Presentation

Local draft for the repository's About fields and a short walkthrough. Editing this file does not update GitHub settings.

## Proposed repository description

Terraform S3/KMS security lab with public access blocking, versioning, lifecycle controls, and GitHub Actions validation and IaC scanning.

## Proposed topics

`terraform`, `aws`, `amazon-s3`, `aws-kms`, `cloud-security`, `infrastructure-as-code`, `github-actions`

## Short introduction

Secure AWS Platform currently implements a single-region S3/KMS development foundation in Terraform. It defines public access blocking, bucket-owner-enforced ownership, versioning, default customer-managed KMS encryption with rotation, and storage lifecycle rules. GitHub Actions checks formatting, validates the configuration, runs TFLint, and blocks unsuppressed Checkov findings. The next milestone is to define and test the access boundary, followed by protected state and one observable detection and restoration scenario.

The [deployed storage milestone](storage-policy-contract.md) adds a deny-only request policy, account/development safeguards, and regression tests. Four mocked plan tests and seven deliberate regressions pass locally. The reviewed plan was applied to the existing bucket, 20 verification checks passed, and the final plan showed no changes. Hosted CI has not run the local changes.

## Five-minute walkthrough

1. **Start with scope.** Open the [README](../README.md). Identify the implemented S3/KMS configuration and the separate planned-work table.
2. **Inspect storage controls.** Open [main.tf](../terraform/environments/dev/main.tf). Show the four public-access-block settings, disabled ACLs, and versioning. Explain that authenticated access policies remain outside the implementation.
3. **Explain encryption and retention.** Open [kms.tf](../terraform/environments/dev/kms.tf) and [lifecycle.tf](../terraform/environments/dev/lifecycle.tf). Distinguish default encryption from required-key enforcement, and versioning from immutable retention. Point out the default key policy and destructive lab teardown settings.
4. **Show the available evidence.** Open the [recorded CI run](https://github.com/jayekwere/secure-aws-platform/actions/runs/40050245606): three passing jobs and a Checkov result of 18 passed, 0 failed, 4 skipped. Use the [suppression decisions](phase-1-secure-s3-foundation.md#checkov-finding-decisions) to explain the remaining gaps. The run demonstrates static checks, not live authorization or detection.
5. **Close with the next verifiable outcome.** Show the [roadmap](../README.md#prioritized-planned-work): allowed and denied S3/KMS operations, negative regression tests, protected state, and a detected bucket configuration change with documented restoration.

## Boundaries to state alongside the demonstration

- Historical deployment notes and the later read-only console inspection have different evidence limits. The console inspection found the original bucket and checked selected settings; it did not prove authorization or full state reconciliation.
- The bucket policy is applied and verified with synthetic uploads, downloads, denials, and multipart requests. Managed workload roles, an explicit KMS key policy, remote state, private networking, detection, OIDC deployment, and application workloads remain future work.
- Containers, EKS, Kubernetes policies, and admission control are longer-term possibilities. They are not current project capabilities.
- The local development configuration now rejects production labels and requires explicit opt-in for destructive bucket cleanup. It remains a disposable lab.

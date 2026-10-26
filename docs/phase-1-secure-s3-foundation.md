# Phase 1: S3/KMS Foundation (Historical Baseline)

## Scope and evidence

This page records the implementation at commit `f34d2dc`: a single-region S3 development lab with customer-managed KMS default encryption and automated static validation. Source links below refer to that baseline. Subsequent local policy, safeguard, and test changes are described in the [storage policy milestone](storage-policy-contract.md).

The [learning log](learning-log.md) records manual deployments and verification in July and August 2026. Those are historical reports: raw AWS CLI results and saved deployment plans are not committed. The initial October 25 review inspected source, CI, and static Terraform checks. A later read-only console inspection found the original bucket; its limited observations are recorded in the [milestone notes](storage-policy-contract.md#read-only-console-observations). Reconciliation and storage authorization checks were still outstanding at that inspection; the [subsequent deployed milestone](storage-policy-contract.md) records their completion.

## Resources managed

The baseline's nine resource blocks are in one root module; it has no reusable child modules.

| Resource | Purpose | Source |
| --- | --- | --- |
| `random_id.bucket_suffix` | Random suffix to reduce bucket-name collisions | [main.tf](https://github.com/jayekwere/secure-aws-platform/blob/f34d2dc1ca354be9c1cc766cf2fb586360ef806e/terraform/environments/dev/main.tf) |
| `aws_s3_bucket.secure_data` | Development data bucket | [main.tf](https://github.com/jayekwere/secure-aws-platform/blob/f34d2dc1ca354be9c1cc766cf2fb586360ef806e/terraform/environments/dev/main.tf) |
| `aws_s3_bucket_public_access_block.secure_data` | Four bucket public-access-block settings | [main.tf](https://github.com/jayekwere/secure-aws-platform/blob/f34d2dc1ca354be9c1cc766cf2fb586360ef806e/terraform/environments/dev/main.tf) |
| `aws_s3_bucket_ownership_controls.secure_data` | Bucket-owner-enforced ownership | [main.tf](https://github.com/jayekwere/secure-aws-platform/blob/f34d2dc1ca354be9c1cc766cf2fb586360ef806e/terraform/environments/dev/main.tf) |
| `aws_s3_bucket_versioning.secure_data` | Object versioning | [main.tf](https://github.com/jayekwere/secure-aws-platform/blob/f34d2dc1ca354be9c1cc766cf2fb586360ef806e/terraform/environments/dev/main.tf) |
| `aws_s3_bucket_server_side_encryption_configuration.secure_data` | Default SSE-KMS encryption and S3 Bucket Key | [main.tf](https://github.com/jayekwere/secure-aws-platform/blob/f34d2dc1ca354be9c1cc766cf2fb586360ef806e/terraform/environments/dev/main.tf) |
| `aws_kms_key.secure_data` | Customer-managed encryption key | [kms.tf](https://github.com/jayekwere/secure-aws-platform/blob/f34d2dc1ca354be9c1cc766cf2fb586360ef806e/terraform/environments/dev/kms.tf) |
| `aws_kms_alias.secure_data` | Environment-named key alias | [kms.tf](https://github.com/jayekwere/secure-aws-platform/blob/f34d2dc1ca354be9c1cc766cf2fb586360ef806e/terraform/environments/dev/kms.tf) |
| `aws_s3_bucket_lifecycle_configuration.secure_data` | Multipart-upload cleanup and noncurrent-version expiration | [lifecycle.tf](https://github.com/jayekwere/secure-aws-platform/blob/f34d2dc1ca354be9c1cc766cf2fb586360ef806e/terraform/environments/dev/lifecycle.tf) |

## Controls defined in code

### Public access and ownership

All four bucket public-access-block settings are `true`: block public ACLs, ignore public ACLs, block public bucket policies, and restrict public buckets. Object ownership is `BucketOwnerEnforced`, disabling ACL-based access control.

These settings address public exposure and ACL ownership. They do not define which authenticated IAM principals may read, write, or administer the bucket. No IAM or bucket policy is managed by this configuration.

### Encryption and key management

Default encryption uses `aws:kms` and the customer-managed key ARN. Automatic key rotation and the S3 Bucket Key are enabled.

The default is not an exclusive-key enforcement policy. Upload encryption headers can override bucket defaults, and existing objects are not re-encrypted when defaults change. The historical SSE-S3-to-SSE-KMS update therefore does not prove that every existing object uses this key. See [AWS default-encryption behavior](https://docs.aws.amazon.com/AmazonS3/latest/userguide/default-bucket-encryption.html).

No explicit key policy is defined. AWS's default programmatic key policy permits the owning account to delegate permissions through IAM; it does not directly grant every IAM principal key access. Intended key administrators and users still need to be encoded and tested. See [AWS default key policy](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-default.html).

There is no bucket-wide policy denying insecure transport. SSE-KMS object requests themselves require TLS, as described in [AWS SSE-KMS requirements](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html).

### Versioning, lifecycle, and deletion

Versioning is enabled. The lifecycle configuration aborts incomplete multipart uploads after 7 days and expires noncurrent versions after 30 days.

The bucket uses `force_destroy = true`, allowing Terraform to remove contents and object versions during teardown. The KMS key has a 7-day deletion window. These settings suit disposable lab data; they do not establish immutable retention, a backup strategy, or production deletion protection.

### Input validation and resource identification

The region input is restricted to `us-east-2`, `ca-central-1`, or `ca-west-1`, with `us-east-2` as the default. The environment input accepts `dev`, `test`, or `prod`, with `dev` as the default.

Only the development root module exists. Selecting `prod` changes names and tags without adding safeguards or account isolation. It does not make this a production-ready configuration.

Provider defaults tag AWS resources with project, environment, management method, and repository. The S3 bucket and KMS key also carry purpose and data-classification tags. The configuration does not define tag-based authorization policies.

## Authentication assumptions

Earlier deployments are recorded as using IAM user authentication to assume `CloudAdministratorRole` and supply temporary STS credentials to Terraform.

That role and its trust and permission policies are not defined in this repository. The AWS provider uses externally supplied credentials; it does not configure role assumption or restrict the target account. GitHub OIDC and workload reader/writer roles remain planned.

No credentials are needed for the static CI jobs. They do not authenticate to AWS or deploy infrastructure.

## Validation and historical deployment record

The [recorded hosted run](https://github.com/jayekwere/secure-aws-platform/actions/runs/40050245606) for commit `f34d2dc` passed on October 23, 2026, Vancouver time:

- Terraform formatting, backend-disabled initialization, and validation passed.
- TFLint 0.64.0 passed using the Terraform recommended ruleset.
- Checkov 3.3.30 reported 18 passed, 0 failed, and 4 skipped checks.

Local formatting, backend-disabled initialization with `-lockfile=readonly`, and provider validation also passed during the October 25 review using Terraform 1.15.8. The [README](../README.md#run-the-static-checks) contains commands for repeating the static checks.

The historical deployment notes record this sequence:

```text
terraform init
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform state list
terraform plan
```

They report a post-deployment plan returning:

```text
No changes. Your infrastructure matches the configuration.
```

That is a historical report of reconciliation at the time of the plan. It is not retained raw plan evidence, continuing drift monitoring, or proof that unauthorized operations are denied. There are no committed Terraform tests, deliberately insecure fixtures, or live authorization tests.

## Read-only AWS verification

For an existing lab, run from the repository root with its active backend initialized and temporary credentials authorized for the read operations below. The current deployment uses protected remote state; local recovered states are archives. State supplies resource identifiers; the AWS queries inspect live settings. If the state or resources are absent, stop and establish the lab's status rather than treating missing output as a passing result.

Confirm the returned account and role before querying resources:

```sh
aws sts get-caller-identity

LAB_BUCKET="$(terraform -chdir=terraform/environments/dev output -raw bucket_name)"
LAB_KMS_KEY="$(terraform -chdir=terraform/environments/dev output -raw kms_key_arn)"
LAB_REGION="$(terraform -chdir=terraform/environments/dev output -raw aws_region)"

aws s3api get-public-access-block --bucket "$LAB_BUCKET" --region "$LAB_REGION"
aws s3api get-bucket-ownership-controls --bucket "$LAB_BUCKET" --region "$LAB_REGION"
aws s3api get-bucket-versioning --bucket "$LAB_BUCKET" --region "$LAB_REGION"
aws s3api get-bucket-encryption --bucket "$LAB_BUCKET" --region "$LAB_REGION"
aws s3api get-bucket-lifecycle-configuration --bucket "$LAB_BUCKET" --region "$LAB_REGION"
aws kms describe-key --key-id "$LAB_KMS_KEY" --region "$LAB_REGION"
aws kms get-key-rotation-status --key-id "$LAB_KMS_KEY" --region "$LAB_REGION"
aws kms get-key-policy --key-id "$LAB_KMS_KEY" --policy-name default --region "$LAB_REGION"
```

Compare public access, ownership, versioning, encryption, rotation, and lifecycle results with the settings above. Inspect the actual key policy separately because Terraform does not define one. These queries do not test whether specific principals can read or write objects, or whether existing objects use the intended key.

The commands are a verification procedure, not a new result. Retain dated, sanitized output when repeating it; keep credentials, state, saved plans, and sensitive identifiers out of published evidence.

## State management

State is local; no remote backend is configured. [Ignore rules](../.gitignore) exclude Terraform state, saved plans, and downloaded provider files from ordinary Git adds. They do not encrypt state, establish centralized access controls, or prevent a forced commit.

A separately bootstrapped remote backend with encryption, scoped access, versioning, shared locking, and recovery verification is planned. No state migration was performed as part of the documentation review.

## Checkov finding decisions

The project history documents these six decisions. Four resource-scoped suppressions were present in this baseline and remain unresolved by the local policy milestone.

| Check | Decision | Current implementation or gap |
| --- | --- | --- |
| `CKV_AWS_145` | Remediated | Customer-managed KMS default encryption configured |
| `CKV2_AWS_61` | Remediated | S3 lifecycle configuration added |
| `CKV_AWS_18` | Deferred; suppressed | No S3 access logging; dedicated log destination planned |
| `CKV2_AWS_62` | Deferred; suppressed | No EventBridge notifications; detection workflow planned |
| `CKV_AWS_144` | Accepted for this lab; suppressed | No cross-region replication for temporary single-region development data |
| `CKV2_AWS_64` | Deferred; suppressed | Explicit least-privilege KMS key policy absent |

The suppressions include phase-based reasons, but do not carry owners, expiry dates, or automated expiry checks. Blocking Checkov behavior does not make suppressed controls implemented.

## Next milestone

The subsequent [deployed milestone](storage-policy-contract.md) adds a request policy, input safeguards, and mocked regression tests. The original state was recovered and reconciled, the reviewed plan applied, and synthetic live requests verified. Workload IAM/key-policy boundaries, remote state, and logging/detection were subsequently deployed and verified in the [access/audit/state milestone](phase-2-access-audit-state.md). Further work is on the [current roadmap](../README.md#next-steps).

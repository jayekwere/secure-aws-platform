# Storage Policy Milestone

## Status

The reviewed policy and safer teardown setting were applied to the original development bucket on October 26, 2026. Terraform added one policy, changed one bucket-management setting, and destroyed no resources. Twenty verification checks passed; the post-apply plan reported no changes. Hosted CI has not run these local changes.

The original serial-12 state was recovered from the original project checkout and matched to the existing bucket and KMS key. An unchanged copy was preserved privately before applying the reviewed plan. The active state is now serial 15 in this checkout's development directory. The original checkout's state remains an unchanged pre-apply archive: do not use it for further Terraform operations. State, backups, raw plans, and apply logs are private and ignored by Git.

## Intended request contract

[bucket-policy.tf](../terraform/environments/dev/bucket-policy.tf) contains three deny statements:

| Statement | Applied effect |
| --- | --- |
| `DenyInsecureTransport` | Deny HTTP requests by non-service principals on the bucket and its objects. The AWS service-principal exception follows AWS transport-context guidance and grants no permissions. |
| `DenyUnexpectedEncryption` | Deny uploads unless the encryption header explicitly requests `aws:kms`. Missing headers and SSE-S3 requests are denied. |
| `DenyUnexpectedKmsKey` | Require a key identifier resolving to the approved project key ARN. Missing key headers and another existing key were explicitly denied. A valid alias resolving to the approved key was accepted. |

Both encryption headers are required even though bucket default encryption remains configured. Clients relying on implicit default encryption need to change. Existing objects are not migrated. Multipart uploads were verified successfully; AWS service integrations remain untested.

The policy grants no read, write, or administrator access. Reader/writer roles and an explicit KMS key policy remain future work; the current key policy is externally managed.

The provider now requires a 12-digit `expected_account_id` and sets `allowed_account_ids`. Supply the intended account ID through an uncommitted variable file or environment variable before any real plan. The root module accepts only `environment = "dev"`.

Destructive bucket cleanup defaults to `allow_force_destroy = false`. Setting it to `true` explicitly permits removal of contents during lab teardown; it is not needed for validation or mocked tests. The KMS deletion window remains 7 days.

## Executable verification

Run from the repository root after installing Terraform 1.15.8 and Python 3:

```sh
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/dev init -backend=false -input=false -lockfile=readonly
terraform -chdir=terraform/environments/dev validate -no-color
python3 scripts/check_storage_regressions.py
```

The runner copies configuration into temporary directories, removes AWS credential environment variables, disables credential-file and instance-metadata lookup, and uses mocked providers with synthetic identifiers. It runs four positive/expected-input-failure plan tests, then seven deliberately changed configurations. Each changed configuration must validate successfully and fail the intended security assertion. A provider startup error or unrelated test failure does not count as detection.

The [local result](evidence/storage-policy-tests-local.json) records four passing plan tests and detection of all seven mutations: public ACL protection disabled, key rotation disabled, forced cleanup enabled by default, transport condition reversed, wrong encryption algorithm, wrong KMS key, and an allow replacing a deny. Source hashes bind that result to the tested Terraform files, tests, lockfile, and runner.

The mocked results prove configuration regression checks. A subsequent reviewed, provider-backed plan was applied and verified separately against AWS; the live results below do not turn this lab into a production-ready platform.

The [local Checkov scan](evidence/storage-checkov-local.json) used the exact Checkov 3.3.30 image digest from the recorded hosted run, with the source mounted read-only and container networking disabled. It reported 19 passed, 0 failed, 4 skipped, and 0 parsing errors across 10 resources. The original four suppressions remain active.

[TFLint 0.64.0](evidence/storage-tflint-local.json) also reported no issues or errors using the existing Terraform recommended ruleset in a read-only, network-disabled container. Its result records the image digest and source hashes. The AWS ruleset remains unconfigured.

## Read-only console observations

The signed-in IAM user's bucket inventory request was denied. Switching to the existing `CloudAdministratorRole` allowed inspection of the original project bucket in `us-east-2`.

Observed directly:

- All four bucket public-access-block settings were on.
- Object ownership was bucket owner enforced, with ACLs disabled.
- Bucket versioning was enabled.
- Default encryption was SSE-KMS using a customer-managed key ARN in the project region, with the S3 Bucket Key enabled.
- The `secure-data-retention` lifecycle rule was enabled for the entire bucket; the summary showed noncurrent-version deletion and incomplete-upload cleanup. Detailed day values were not inspected.
- Server access logging was disabled and S3 EventBridge delivery was off.
- The bucket-policy display was empty, with its copy/delete controls disabled.

This is a dated manual observation, not an exported API inventory or continuous drift check. Key rotation, the actual KMS key policy, object encryption, account-wide CloudTrail configuration, and allowed/denied application operations were not inspected. No resource settings, grants, objects, or keys were changed.

## Applied verification

The [live verification record](evidence/storage-live-verification.json) contains 20 passing checks, including:

- Correct-account identity and real provider rejection of an incorrect expected account.
- Public access blocks, disabled ACLs, versioning, default SSE-KMS/Bucket Key, enabled customer-managed key and rotation, and 7/30-day lifecycle settings.
- Applied policy matching the approved plan, and automatic content deletion disabled in Terraform state.
- Approved-key upload and download, plus a valid alias resolving to the approved key.
- Explicit resource-policy denials for missing encryption headers, SSE-S3, a missing key header, and a different existing KMS key.
- Denied anonymous read, successful multipart upload, and exact-version cleanup of all four synthetic objects created across verification probes.
- A final Terraform plan with exit code 0 and no proposed changes.

One invalid probe used a nonexistent KMS key. AWS returned `KMS.NotFoundException` before policy authorization, so that probe is explicitly recorded as inconclusive rather than evidence of policy denial. Live testing also corrected the earlier literal-ARN-only wording: AWS resolves a valid alias to the approved key before checking the key condition.

No signed credentials were sent over HTTP. The non-service transport deny was checked in the applied policy. Workload-role least privilege, explicit KMS key-policy restrictions, centralized logging/detection, remote state, and AWS service integrations remain separate work.

References: [AWS encryption requirements](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html), [AWS transport-policy guidance](https://docs.aws.amazon.com/AmazonS3/latest/userguide/amazon-s3-policy-keys.html#example-bucket-policies-TLS-version), [Terraform provider mocks](https://developer.hashicorp.com/terraform/language/tests/mocking).

# Access, audit, detection and protected state

**Status, October 26, 2026: deployed.** The approved foundation and development controls are applied. The existing data bucket and key were preserved, and both Terraform roots now use the protected S3 backend. [Live verification](evidence/phase2-live-verification.json) and [backend verification](evidence/phase2-state-migration.json) distinguish observed results from configured controls. This milestone does not establish that the entire AWS account is secure.

## Reviewed plans and deployment

| Root | Add | Update | Replace / delete | Purpose |
| --- | ---: | ---: | ---: | --- |
| `terraform/bootstrap` | 18 | 0 | 0 | State bucket, dedicated CMK, shared access-log bucket and protection resources |
| `terraform/environments/dev` | 34 | 1 | 0 | Roles, explicit data-key policy, audit trail, log destinations, security-event queue and rules |

The planned existing-resource update preserved the data-key ARN and key material. It replaces default account IAM delegation with explicit principals and raises the configured deletion window from 7 to 30 days. The administrator retains policy-update access; the lockout safety check remains enabled. The full policy is known in the plan.

The [sanitized original plan inventory and source hashes](evidence/phase2-plan-review.json) identify the pre-approval snapshot. During deployment, AWS rejected creation of the state-key alias because the explicit administrator policy omitted `kms:CreateAlias`. The repair added only `CreateAlias`, `UpdateAlias` and `DeleteAlias` to named key administration in both roots. Terraform then completed bootstrap and dev without replacement or deletion. New negative tests catch this omission. The [deployment evidence](evidence/phase2-deployment.json) identifies the final source and operation counts. Saved binary plans, full text/JSON plans, the previous key policy and a state backup are private files under each root's ignored `.terraform/review/` directory. Do not commit these files. These plan files remain historical review material; use the active remote state and a fresh plan for future operations.

## Access and encryption boundaries

- The reader may list `workloads/` and read object versions beneath it. The writer may upload and manage multipart uploads under that prefix, but cannot read or delete objects. Neither role can access state or audit logs. Only the existing named administrator can assume these roles; there are no workload integrations yet.
- The data CMK permits reader decryption and writer data-key generation/decryption only through regional S3, with this bucket's encryption context. The bucket context supports Bucket Keys; object context preserves compatibility with older objects. S3 IAM policies enforce the object prefix.
- Root recovery permits only key description and policy recovery, conditioned on the actual root principal. It does not delegate account-wide cryptographic use. The named administrator remains powerful and can change policies; this is not an organizational guardrail against that administrator.
- Data, audit and state use distinct keys. All three keys have rotation, a 30-day deletion window, lockout checks and Terraform `prevent_destroy`. That lifecycle setting does not prevent someone disabling a key directly in AWS.
- CloudTrail access to the audit CMK and bucket is limited to this trail. Regional CloudWatch encryption is limited to the exact project log-group context. CloudTrail's role can write only the account's trail streams in that group.

## Logging and detection

The deployed multi-region trail records management writes, management reads except KMS reads, and object operations on the project data/state buckets. The KMS-read exclusion reduces volume; direct decrypt/read operations therefore do not have comprehensive trail coverage. Object events on log destinations are excluded to prevent feedback loops. Trail integrity validation is enabled.

The archive and CloudWatch log group retain current logs for 365 days. Expired archive versions remain for another 90 days. Data, state and archive server access logs go to a separate versioned SSE-S3 bucket; that terminal bucket does not log into itself. AWS requires SSE-S3 for an S3 server-access-log destination. [S3 encryption requirements](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html), [delivery permissions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/enable-server-access-logging.html).

Four regional EventBridge rules capture project bucket configuration changes, regional key security changes, workload/state object deletion, and trail changes. The KMS rule covers all keys in the region. Events enter an encrypted SQS queue with 14-day retention; failed EventBridge deliveries use a separate queue. CloudWatch queue alarms make pending messages visible. **Free account-level email routing was added during closeout; contact verification and receipt testing are recorded separately.** No automatic remediation or continuously running consumer is configured. These rules are not a replacement for GuardDuty or account-wide monitoring. Events in other regions have trail coverage but no corresponding regional rule deployment.

## Local verification and limits

- Native plan tests cover the storage request policy, input guards, bounded roles/key use, service-delivery permissions, event targets and protected-backend settings. The mutation runner requires the intended assertion to reject each deliberately weakened configuration; validation errors and crashes do not count as detections.
- [Dev tests and mutations](evidence/phase2-dev-tests-local.json): five plan runs and 13 deliberate regressions; [bootstrap tests and mutations](evidence/phase2-bootstrap-tests-local.json): one plan run and five deliberate regressions.
- [EventBridge pattern checks](evidence/phase2-event-patterns.json) use AWS's read-only evaluator with 15 positive/negative synthetic fixtures, including unrelated buckets, normal lock releases and cross-bucket key confusion. No events were published. This proves matching semantics; actual delivery is demonstrated separately in the live record.
- [Checkov evidence](evidence/phase2-checkov-local.json): 123 passed, 0 failed, 9 explicitly skipped, 0 parsing errors. [TFLint evidence](evidence/phase2-tflint-local.json): both roots clean using the Terraform ruleset. The workflow validates both roots without AWS credentials. [Hosted CI](https://github.com/jayekwere/secure-aws-platform/actions/runs/40346124360) passed all five jobs for `bb56adf`.
- The old `storage-*` evidence files describe the earlier deployed baseline and retain its original source hashes. They do not attest to the later IAM/logging/state milestone.

### Scanner exceptions

Checkov exceptions are resource-specific comments, not a global soft-fail. Reassess these decisions before broadening beyond a temporary single-region lab:

| Check | Resource | Reason / remaining gap |
| --- | --- | --- |
| `CKV_AWS_144` | Data, state, access logs, audit | No cross-region replication. Versioning does not cover region loss. |
| `CKV_AWS_18` | Terminal access-log bucket | Avoid recursive self-logging; other source buckets have access logging. |
| `CKV_AWS_145` | Terminal access-log bucket | SSE-S3 is required for this delivery service; public blocking, source restrictions and TLS still apply. |
| `CKV2_AWS_62` | Terminal access logs, audit | No log-object notifications; bucket management changes are monitored. |
| `CKV_AWS_252` | Trail | Security events use SQS and visible alarms. Separate free AWS User Notifications routes the existing queue alarms to email; no SNS topic is needed. Contact activation/receipt has separate evidence. |

These archives are not immutable. There is no Object Lock, cross-account log isolation, enforced exception expiry, required GitHub checks in this milestone. A separate free account-budget warning was configured during closeout; it is not managed by project Terraform.

## Deployment and live verification

- Applied bootstrap before dev. Bootstrap created 18 resources in total; its newly created key received one narrow alias-administration repair. Dev created 34 resources and updated the existing data key. No resources were replaced or destroyed.
- Passed actual reader/writer/admin requests: encrypted writer upload and reader download, version reads, multipart compatibility, denied opposite-role operations, denied deletion/outside-prefix access, denied direct KMS use, and denied state/audit access. All synthetic object versions were removed by exact version ID.
- Observed an encrypted CloudTrail archive object, CloudWatch log events, and a real synthetic security probe in SQS. Queue messages were retained, not purged. The delivery DLQ and queue-alarm observations are recorded in [live evidence](evidence/phase2-live-verification.json).
- Migrated dev and bootstrap state to separate keys in the protected backend. Compared full resource inventories and outputs. The [state evidence](evidence/phase2-state-migration.json) records lineage/serial transitions, actual lock contention, recovery and final plan results; only recorded passing checks are claimed.

New recurring charges include two customer-managed keys, CloudTrail data events, log ingestion/storage, S3 requests/storage, SQS/EventBridge usage and two alarms. No fixed monthly estimate is claimed; usage and regional pricing determine the cost.

## State migration after deployment

The partial `backend.tf` blocks are active in both roots. The migration procedure below records the completed approach; do not re-run it on an already migrated workspace. The bootstrap output supplies encryption and native S3 lockfile settings. Workload roles have no backend access. The bucket policy denies deletion of the two exact state keys while permitting normal `.tflock` removal. Noncurrent versions expire after 90 days; current state does not expire. Lifecycle cleanup is not immutable retention.

Use Terraform 1.15.8 with the named administrator session. For an existing deployment in a fresh checkout, initialize these blocks with the authorized private backend files. To bootstrap a new disposable account, first create the foundation using local state with its backend block temporarily outside the root, then activate the block and migrate into the checked-empty bucket. The following records the reviewed migration approach; it is not a command to overwrite existing state. Generate private HCL backend files from the bootstrap output. Run from the repository root:

```sh
umask 077
terraform -chdir=terraform/bootstrap output -json state_backend > terraform/environments/dev/.terraform/review/backend-input.json
python3 - <<'PY'
import json
from pathlib import Path
dev = Path('terraform/environments/dev')
config = json.loads((dev / '.terraform/review/backend-input.json').read_text())
for directory, key in [(dev, 'environments/dev/terraform.tfstate'),
                       (Path('terraform/bootstrap'), 'bootstrap/terraform.tfstate')]:
    config['key'] = key
    path = directory / '.terraform/review/state.s3.tfbackend'
    path.write_text(''.join(f'{name} = {json.dumps(value)}\n' for name, value in config.items()))
PY
cp terraform/environments/dev/terraform.tfstate terraform/environments/dev/.terraform/review/before-migration.tfstate
cp terraform/bootstrap/terraform.tfstate terraform/bootstrap/.terraform/review/before-migration.tfstate
terraform -chdir=terraform/environments/dev init -migrate-state -backend-config=.terraform/review/state.s3.tfbackend
```

Review Terraform's migration prompt; do not force-copy over an existing remote state. The state and lockfile both receive SSE-KMS headers when `encrypt` and `kms_key_id` are set. [Backend documentation](https://developer.hashicorp.com/terraform/language/backend/s3), [Terraform 1.15.8 implementation](https://github.com/hashicorp/terraform/blob/v1.15.8/internal/backend/remote-state/s3/client.go).

Bootstrap uses its **own** backend file/key. Migration allocated new remote lineage IDs and restarted serial numbering; exact resource inventories and outputs were preserved. Local pre-migration states remain private recovery archives. Use the current remote lineage for future operations, not the old local state. Operational verification compares both states and tests the real backend; see the [recorded outcomes](evidence/phase2-state-migration.json).

Key-policy design follows AWS's [CloudTrail encryption guidance](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/create-kms-key-policy-for-cloudtrail.html), [CloudWatch encryption context guidance](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html), and [bounded EventBridge delivery permissions](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-use-resource-based.html).

## October 27 notification closeout

The existing email channel is now Active. A synthetic delivery-DLQ alarm event reached the notification center and the recipient confirmed its email. The alarm was restored to its original OK state. [Exact timestamps, bounded reproduction and limitations](notification-verification.md) supersede earlier pending-verification notes; the original October 26 evidence remains historical. The [pinned-workflow CI record](evidence/pinned-workflow-hosted.json) separately records all five passing jobs, six mocked plan runs and 18 rejected deliberate regressions.

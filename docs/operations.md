# Operating and resuming the foundation

The deployed foundation has two independent Terraform roots and existing S3 state. Use this guide to resume it from a fresh checkout. It does not create a new AWS account or bootstrap a second deployment.

## Before making changes

- Use the existing lab account, deployment region and `CloudAdministratorRole`. Keep the intended account ID in your private configuration; do not infer authorization just from whichever account happens to be signed in.
- Remote state is authoritative. Original local states and private recovery files are archives. Do not import resources, copy old state over the backend, or use `-force`, `-force-copy` or `-lock=false` to bypass a mismatch.
- Run one root at a time. A change can pass source checks and still require a reviewed AWS plan and live verification.

## Sign in from a fresh Mac or checkout

Install AWS CLI v2 with `aws login`, Terraform 1.15.8 and Git. Clone the repository, then run commands from its root. No permanent access keys are needed. The tested provider-lockfile platforms are Apple silicon (`darwin_arm64`) and Linux x86-64 (`linux_amd64`); prepare and review official provider checksums for another architecture without changing provider versions or bypassing lockfile checks. Use a fresh terminal or remove stale exported temporary AWS credentials before selecting the profile.

```sh
aws configure set region us-east-2 --profile cloud-admin
aws login --profile cloud-admin --region us-east-2
aws configure set credential_process 'aws configure export-credentials --profile cloud-admin --format process' --profile secure-aws-platform
export AWS_PROFILE=secure-aws-platform
export AWS_REGION=us-east-2
export TF_VAR_expected_account_id="YOUR_12_DIGIT_LAB_ACCOUNT_ID"
```

During sign-in, select the existing administrator role in the intended lab account. The credential-process profile lets Terraform and its backend obtain temporary credentials without printing or storing access keys in the repository.

The following reconstructs the non-secret backend settings from the account, region and deployed state-key alias. It verifies identity and both existing state objects before writing private settings. It stops if the expected deployment cannot be found.

```sh
python3 - <<'PY'
import json, os, re, subprocess
from pathlib import Path

def aws(*args):
    return json.loads(subprocess.check_output(['aws', *args, '--output', 'json'], text=True))

expected = os.environ['TF_VAR_expected_account_id']
region = os.environ['AWS_REGION']
assert re.fullmatch(r'[0-9]{12}', expected), 'Set the known lab account ID first.'
identity = aws('sts', 'get-caller-identity')
assert identity['Account'] == expected, 'Wrong AWS account.'
assert ':assumed-role/CloudAdministratorRole/' in identity['Arn'], 'Use the existing administrator role.'
key = aws('kms', 'describe-key', '--key-id', 'alias/secure-aws-platform-state', '--region', region)['KeyMetadata']
assert key['Enabled'], 'The state key must be enabled.'
bucket = f'secure-aws-platform-state-{expected}-{region}'
os.umask(0o077)
for root, state_key in [('terraform/environments/dev', 'environments/dev/terraform.tfstate'),
                        ('terraform/bootstrap', 'bootstrap/terraform.tfstate')]:
    head = aws('s3api', 'head-object', '--bucket', bucket, '--key', state_key, '--region', region)
    assert head['ServerSideEncryption'] == 'aws:kms' and head['SSEKMSKeyId'] == key['Arn']
    config = dict(bucket=bucket, key=state_key, region=region, encrypt=True,
                  kms_key_id=key['Arn'], use_lockfile=True, allowed_account_ids=[expected])
    path = Path(root) / '.terraform/review/state.s3.tfbackend'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(f'{name} = {json.dumps(value)}\n' for name, value in config.items()))
print('Identity, encryption and both existing state objects verified; private backend files prepared.')
PY
terraform -chdir=terraform/bootstrap init -reconfigure -input=false -lockfile=readonly -backend-config=.terraform/review/state.s3.tfbackend
terraform -chdir=terraform/environments/dev init -reconfigure -input=false -lockfile=readonly -backend-config=.terraform/review/state.s3.tfbackend
```

This attaches a checkout to existing state; it is not a state migration. Backend files are ignored by Git and contain no credentials. Keep recovery material in protected private storage.

## Establish a clean starting point

Read the [deployment record](phase-2-access-audit-state.md) and [verification evidence](evidence/phase2-live-verification.json). Obtain the current data bucket name from state for the bootstrap variable, then plan both roots:

```sh
export TF_VAR_data_bucket_name="$(terraform -chdir=terraform/environments/dev output -raw bucket_name)"
terraform -chdir=terraform/bootstrap plan -detailed-exitcode
terraform -chdir=terraform/environments/dev plan -detailed-exitcode
```

Exit code `0` means no changes, `2` means proposed changes, and `1` means an error. Investigate a changed plan before applying it. If the key, bucket, account, region or state lineage differs unexpectedly, stop and reconcile the discrepancy.

## Build the next increment

1. Define one outcome and its allowed/denied behavior. Keep this foundation's existing controls and evidence as the baseline.
2. Make the source change and run the [static checks](../README.md#run-the-static-checks). Add meaningful regression coverage for the new boundary.
3. Save a private plan and review resource actions, permission changes, dependency order and cost. Bootstrap changes precede dependent dev changes.
4. Apply the reviewed saved plan using the administrator session. Use synthetic development data for verification and remove only the test objects/versions created by that run.
5. Verify the intended behavior, retain sanitized evidence, obtain a final no-change plan, update documentation and publish with passing CI.

## Review monitoring and cost

- Poll the `security_queue_urls` output's events queue and delivery DLQ; inspect the queue alarms. The deployment demonstrated event delivery, not a continuously staffed response process.
- Confirm CloudTrail is logging and delivering to both destinations. S3 access-log delivery and full digest-chain validation have separate evidence limits.
- Separate account-level AWS User Notifications routing watches the two queue alarm ARNs entering `ALARM` in the deployment region. It uses an email contact and no additional customer-managed key or SNS topic. Verify the contact before expecting email; this path does not replay an alarm's historical state. The configuration is outside project Terraform state, so inspect it separately on handoff. See the [notification record](evidence/security-notification-configuration.json) and [AWS notification guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Notify_Users_Alarm_Changes.html).
- A free actual-cost warning above US$0.01 is configured on an existing account budget. Existing budget limits and other notifications were preserved. Recipient verification/receipt must be confirmed; no charge was generated for testing. See the [cost-alert record](evidence/cost-alert-configuration.json).
- The current three customer-managed keys alone have a list-price storage cost of roughly US$3/month before rotation history, requests, logging/storage and credits. Keeping the complete live architecture is not a zero-cost configuration. See [AWS KMS pricing](https://aws.amazon.com/kms/pricing/).
- Budget monitoring and alerts are free, but alerts are delayed notifications rather than a spending cap. A near-zero alert threshold does not prevent charges. Avoid paid budget reports or automated budget actions unless explicitly needed. See [Budgets pricing](https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/) and [notification limits](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html).
- For near-zero ongoing cloud usage, preserve the source/evidence and review a dedicated decommissioning plan. Export and protect current state before considering deletion of its backend or keys. No shutdown is implicit in the completed foundation milestone.
- Check the account plan before future milestones. A Free plan ends when its period or credits run out; preserve recovery copies outside that account. Some features, including AWS Organizations and Control Tower, can upgrade a Free plan automatically. No plan upgrade was performed for this milestone. See [AWS account-plan rules](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html).

## Recovery and teardown

Both state keys have encrypted version history and native locking. Prior versions were retrieved privately during verification; the active state was not rolled back. If recovery is needed, back up current state, compare inventory/lineage/serial and plan a reviewed restoration. Do not delete protected state versions to test a deny policy.

Terraform deletion guards protect keys and foundation/archive resources. `allow_force_destroy` is an explicit data-bucket cleanup opt-in, not a complete teardown procedure. Before decommissioning, identify state and retained data dependencies, preserve the required recovery copies and review a dedicated teardown plan. Do not delete the state bucket or disable its key while either root still depends on it.

The account root can recover key policies; that is an emergency path, not routine administration. Root recovery and destructive teardown were not exercised by the live tests.

## Recreate account-level alert routing if needed

These settings are separate from Terraform and should be checked after changing accounts or rebuilding the lab:

1. In AWS User Notifications, register a notification hub in the deployment region and create the `secure-aws-platform-security` configuration without aggregation.
2. Select CloudWatch, `CloudWatch Alarm State Change`, and `us-east-2`. Restrict the advanced filter to the exact ARNs of `secure-aws-platform-dev-events-pending` and `secure-aws-platform-dev-delivery-dlq-pending`, with `detail.state.value` equal to `ALARM`. Obtain current ARNs from CloudWatch; do not reuse another account's identifiers.
3. Associate the operator's email contact and complete its verification. Inspect event-rule regional status and channel association. Use the [AWS example filter](https://docs.aws.amazon.com/notifications/latest/userguide/common-usecases.html) when reconstructing the rule.
4. Add an actual-cost `GREATER_THAN` notification with an `ABSOLUTE_VALUE` threshold of US$0.01 to the existing project cost budget and the operator-approved recipient. Preserve other notifications. Monitoring and email alerts are free; budget reports and some automated actions have separate pricing.
5. Verify security notification receipt using a clearly labeled synthetic alarm test only when no real delivery failure is present. Restore normal metric evaluation and retain evidence. Do not create a charge just to test the budget warning.

## October 27 notification closeout

The existing email channel is now Active. A synthetic delivery-DLQ alarm event reached the notification center and the recipient confirmed its email. The alarm was restored to its original OK state. [Exact timestamps, bounded reproduction and limitations](notification-verification.md) supersede earlier pending-verification notes; the original October 26 evidence remains historical. The [pinned-workflow CI record](evidence/pinned-workflow-hosted.json) separately records all five passing jobs, six mocked plan runs and 18 rejected deliberate regressions.

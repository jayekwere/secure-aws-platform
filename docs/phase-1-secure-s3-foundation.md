
```text
aws:kmsThe bucket explicitly uses S3-managed server-side encryptionThe bucket explicitly uses S3-managed server-side encryption

# Phase 1: Secure S3 Foundation


## Objective

Deploy and verify a secure-by-default Amazon S3 bucket using Terraform.

## Resources Managed

Terraform creates and manages:

- A random identifier for global bucket-name uniqueness
- An Amazon S3 bucket
- S3 public-access-block settings
- S3 object ownership controls
- S3 versioning
- S3 server-side encryption

## Security Controls

### Public Access Protection

All four S3 public-access-block controls are enabled:

- Block public ACLs
- Ignore public ACLs
- Block public bucket policies
- Restrict public buckets

### Object Ownership

The bucket uses:

```text
BucketOwnerEnforced
```

This disables ACL-based access control and makes access policy-based.

### Versioning

Object versioning is enabled to improve recovery from accidental deletion or overwrite.

Versioning is not a complete backup strategy, but it provides an additional recovery control.

### Encryption

The bucket uses server-side encryption with a customer-managed AWS KMS key:

```text
aws:kms
```

Automatic KMS key rotation is enabled, and an S3 Bucket Key reduces repeated KMS requests for bucket operations.

### Resource Identification

Terraform applies tags identifying:

- Project
- Environment
- Management method
- Repository
- Purpose
- Data classification

## Authentication Model

Terraform authenticates using temporary AWS credentials:

```text
IAM user authentication
        ↓
CloudAdministratorRole
        ↓
AWS STS temporary session
        ↓
Terraform AWS provider
```

No permanent AWS access keys are stored in the repository.

## Terraform Workflow

The deployment followed this workflow:

```text
terraform init
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform state list
terraform plan
```

The post-deployment plan returned:

```text
No changes. Your infrastructure matches the configuration.
```

This demonstrates Terraform idempotency and confirms that no configuration drift was detected.

## Independent AWS Verification

The live controls were verified through AWS CLI commands for:

- Public-access blocking
- Bucket versioning
- Server-side encryption
- Object ownership

## State Management

Terraform state is currently stored locally for this initial learning phase.

The following are excluded from Git:

- Terraform state
- Saved Terraform plans
- Downloaded provider files

A later phase will implement secure remote state with encryption, access controls, and locking.

## Lab Trade-Off

The bucket currently uses:

```hcl
force_destroy = true
```

This is appropriate for a temporary learning environment because Terraform can delete the bucket even when it contains test objects or previous object versions.

A production data bucket would normally use stronger deletion protection and a documented retention strategy.

## Lifecycle Management

The S3 lifecycle policy:

- Aborts incomplete multipart uploads after 7 days
- Deletes noncurrent object versions after 30 days

This limits unnecessary storage accumulation while retaining a defined recovery window.

## Checkov Finding Decisions

The initial Checkov scan reported five findings:

- `CKV_AWS_145`: Remediated with customer-managed KMS encryption
- `CKV2_AWS_61`: Remediated with an S3 lifecycle configuration
- `CKV_AWS_18`: Deferred until the centralized logging phase
- `CKV2_AWS_62`: Deferred until the event-driven remediation phase
- `CKV_AWS_144`: Accepted for the temporary single-region development lab

Deferred controls use resource-scoped Checkov suppressions with documented engineering justification.

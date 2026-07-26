# Secure AWS Platform

A hands-on cloud security engineering project that builds a secure-by-default AWS platform using Terraform, GitHub Actions, containers, Kubernetes, and Amazon Web Services.

## Project Objectives

This project connects five cloud security engineering areas:

1. AWS security architecture
2. Terraform and infrastructure as code
3. CI/CD and software supply chain security
4. Container, Kubernetes, and EKS security
5. Security finding operationalization and automated remediation

## Planned Architecture

The completed platform will include:

- Secure AWS networking
- Least-privilege IAM
- Encrypted S3 storage
- AWS security logging and detection
- Reusable Terraform modules
- GitHub Actions security pipelines
- Short-lived AWS authentication using GitHub OIDC
- Container image scanning
- Kubernetes RBAC and network policies
- Kyverno admission-control policies
- Findings triage and remediation workflows

## Security Principles

- Secure by default
- Least privilege
- No permanent cloud credentials in source control
- Prevention before detection
- Infrastructure changes through reviewed code
- Clear ownership and actionable security findings
- Measurable security coverage
- Time-bound exceptions

## Learning Approach

Every phase follows the same process:

1. Understand the security problem.
2. Build a small component.
3. Test the component.
4. Introduce an insecure configuration.
5. Detect the problem.
6. Remediate the problem.
7. Add a preventive control.
8. Document the engineering decision.

## Project Status

**Current phase:** Repository and local development environment setup.

No AWS infrastructure has been deployed yet.

## Important Security Notice

This repository must never contain:

- AWS access keys
- GitHub tokens
- Passwords
- Private encryption keys
- Terraform state files
- Real production data

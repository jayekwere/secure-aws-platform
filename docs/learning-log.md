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

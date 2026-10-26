#!/usr/bin/env python3
"""Run mocked plan tests, then prove deliberate security regressions are caught."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "terraform/environments/dev"
# Each replacement must match once. An invalid mutant or unrelated failure is an error.
MUTATIONS = [
    ("public-acls", "main.tf", "block_public_acls       = true",
     "block_public_acls       = false", "All four public access protections"),
    ("key-rotation", "kms.tf", "enable_key_rotation     = true",
     "enable_key_rotation     = false", "Default encryption must use"),
    ("implicit-force-destroy", "main.tf", "force_destroy = var.allow_force_destroy",
     "force_destroy = true", "Deleting bucket contents must require"),
    ("insecure-transport", "bucket-policy.tf", '"aws:SecureTransport"       = "false"',
     '"aws:SecureTransport"       = "true"', "The policy must deny non-service HTTP"),
    ("wrong-encryption", "bucket-policy.tf", '"s3:x-amz-server-side-encryption" = "aws:kms"',
     '"s3:x-amz-server-side-encryption" = "AES256"', "Uploads must explicitly request"),
    ("wrong-key", "bucket-policy.tf",
     '"s3:x-amz-server-side-encryption-aws-kms-key-id" = aws_kms_key.secure_data.arn',
     '"s3:x-amz-server-side-encryption-aws-kms-key-id" = "arn:aws:kms:us-east-2:123456789012:key/00000000-0000-0000-0000-000000000002"',
     "The upload policy must be restricted"),
    ("allow-instead-of-deny", "bucket-policy.tf",
     'Sid       = "DenyInsecureTransport"\n        Effect    = "Deny"',
     'Sid       = "DenyInsecureTransport"\n        Effect    = "Allow"',
     "The bucket policy must attach"),
]


def events(output):
    return [json.loads(line) for line in output.splitlines() if line.strip()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, help="Write a sanitized JSON result on success")
    args = parser.parse_args()
    environment = {
        key: value for key, value in os.environ.items()
        if not key.startswith(("AWS_", "TF_"))
    }
    environment.update({
        "AWS_EC2_METADATA_DISABLED": "true",
        "AWS_SHARED_CREDENTIALS_FILE": os.devnull,
        "AWS_CONFIG_FILE": os.devnull,
        "TF_IN_AUTOMATION": "true",
        "TF_INPUT": "false",
        "CHECKPOINT_DISABLE": "1",
    })

    def run(directory, *arguments):
        return subprocess.run(
            ["terraform", f"-chdir={directory}", *arguments],
            env=environment, text=True, capture_output=True, timeout=120, check=False,
        )

    def require_success(result, label):
        if result.returncode:
            raise RuntimeError(f"{label} failed:\n{result.stdout}\n{result.stderr}")

    version = subprocess.run(
        ["terraform", "version", "-json"], env=environment,
        text=True, capture_output=True, timeout=30, check=True,
    )
    report = {
        "schema_version": 1,
        "verified_at_utc": datetime.now(timezone.utc).isoformat(),
        "terraform_version": json.loads(version.stdout)["terraform_version"],
        "method": "Mocked Terraform plans and deliberate source mutations",
        "live_aws_authorization_tested": False,
        "infrastructure_applied": False,
        "source_sha256": {
            str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted([*SOURCE.glob("*.tf"), SOURCE / ".terraform.lock.hcl",
                                *SOURCE.glob("tests/*.tftest.hcl"), Path(__file__).resolve()])
        },
        "mutations": [],
    }
    with tempfile.TemporaryDirectory(prefix="secure-aws-storage-tests-") as temporary:
        workspace = Path(temporary)
        # Providers are shared between serial mocked plans; source and state are not.
        environment["TF_DATA_DIR"] = str(workspace / "provider-data")

        def copy_configuration(name):
            target = workspace / name
            target.mkdir()
            for path in [*SOURCE.glob("*.tf"), SOURCE / ".terraform.lock.hcl"]:
                shutil.copyfile(path, target / path.name)
            shutil.copytree(SOURCE / "tests", target / "tests")
            return target

        baseline = copy_configuration("baseline")
        init_args = ["init", "-backend=false", "-input=false", "-lockfile=readonly", "-no-color"]
        installed = SOURCE / ".terraform/providers"
        if installed.is_dir():
            init_args.append(f"-plugin-dir={installed}")
        require_success(run(baseline, *init_args), "Provider initialization")
        require_success(run(baseline, "validate", "-no-color"), "Baseline validation")
        result = run(baseline, "test", "-json")
        require_success(result, "Baseline mocked tests")
        summary = next(event["test_summary"] for event in events(result.stdout)
                       if event.get("type") == "test_summary")
        report["baseline"] = summary
        print(f"PASS baseline: {summary['passed']} mocked plan tests", flush=True)

        for name, filename, original, replacement, expected in MUTATIONS:
            target = copy_configuration(name)
            path = target / filename
            text = path.read_text()
            if text.count(original) != 1:
                raise RuntimeError(f"{name}: expected exactly one replacement target")
            path.write_text(text.replace(original, replacement))
            require_success(run(target, "validate", "-no-color"), f"{name} mutant validation")
            result = run(target, "test", "-json", "-filter=tests/storage.tftest.hcl")
            diagnostics = [event.get("diagnostic", {}) for event in events(result.stdout)]
            caught = result.returncode == 1 and any(
                item.get("severity") == "error"
                and item.get("summary") == "Test assertion failed"
                and expected in item.get("detail", "")
                for item in diagnostics
            )
            if not caught:
                raise RuntimeError(f"{name}: intended assertion did not fail:\n{result.stdout}\n{result.stderr}")
            report["mutations"].append({"name": name, "detected_by_expected_assertion": True})
            print(f"PASS regression detected: {name}", flush=True)

    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS all {len(MUTATIONS)} deliberate regressions detected; AWS was not accessed", flush=True)


if __name__ == "__main__":
    main()

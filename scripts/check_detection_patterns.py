#!/usr/bin/env python3
"""Test planned EventBridge patterns using AWS's read-only pattern evaluator.

Consumes a private `terraform show -json` plan. Does not create rules, publish
events, change infrastructure, or record account/bucket identifiers in its report.
AWS authentication must already be configured in the calling environment.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text())
    resources = {r["address"]: r["values"] for r in plan["planned_values"]["root_module"]["resources"]}
    patterns = {r["index"]: json.loads(r["values"]["event_pattern"]) for r in plan["planned_values"]["root_module"]["resources"] if r["type"] == "aws_cloudwatch_event_rule"}
    data_bucket = resources["aws_s3_bucket.secure_data"]["bucket"]
    state_bucket = plan["variables"]["expected_account_id"]["value"]
    region = plan["variables"]["aws_region"]["value"]
    state_bucket = f"secure-aws-platform-state-{state_bucket}-{region}"
    account = plan["variables"]["expected_account_id"]["value"]
    prefix = plan["variables"]["workload_prefix"]["value"]
    trail = resources["aws_cloudtrail.project"]["name"]
    trail_arn = f"arn:aws:cloudtrail:{region}:{account}:trail/{trail}"

    def api(service, operation, **parameters):
        return {"source": f"aws.{service}", "detail-type": "AWS API Call via CloudTrail", "detail": {
            "eventSource": f"{service}.amazonaws.com", "eventName": operation, "requestParameters": parameters,
        }}

    def deletion(bucket, key):
        return {"source": "aws.s3", "detail-type": "Object Deleted", "detail": {"bucket": {"name": bucket}, "object": {"key": key}}}

    cases = [
        ("bucket-policy-change", "bucket_controls", True, api("s3", "PutBucketPolicy", bucketName=data_bucket)),
        ("unrelated-bucket", "bucket_controls", False, api("s3", "PutBucketPolicy", bucketName="unrelated-lab-bucket")),
        ("ordinary-bucket-read", "bucket_controls", False, api("s3", "GetBucketPolicy", bucketName=data_bucket)),
        ("key-disabled", "key_controls", True, api("kms", "DisableKey", keyId="synthetic-key")),
        ("ordinary-decrypt", "key_controls", False, api("kms", "Decrypt")),
        ("workload-object-deleted", "object_deletion", True, deletion(data_bucket, f"{prefix}synthetic.txt")),
        ("unrelated-object", "object_deletion", False, deletion(data_bucket, "outside/synthetic.txt")),
        ("dev-state-deleted", "object_deletion", True, deletion(state_bucket, "environments/dev/terraform.tfstate")),
        ("bootstrap-state-deleted", "object_deletion", True, deletion(state_bucket, "bootstrap/terraform.tfstate")),
        ("normal-lock-release", "object_deletion", False, deletion(state_bucket, "environments/dev/terraform.tfstate.tflock")),
        ("state-key-in-data-bucket", "object_deletion", False, deletion(data_bucket, "environments/dev/terraform.tfstate")),
        ("workload-key-in-state-bucket", "object_deletion", False, deletion(state_bucket, f"{prefix}synthetic.txt")),
        ("trail-stopped-by-name", "audit_controls", True, api("cloudtrail", "StopLogging", name=trail)),
        ("trail-stopped-by-arn", "audit_controls", True, api("cloudtrail", "StopLogging", name=trail_arn)),
        ("unrelated-trail", "audit_controls", False, api("cloudtrail", "StopLogging", name="another-trail")),
    ]
    results = []
    for name, rule, expected, payload in cases:
        event = {"version": "0", "id": "00000000-0000-0000-0000-000000000001", "account": account,
                 "time": "2026-10-26T00:00:00Z", "region": region, "resources": [], **payload}
        command = ["aws", "events", "test-event-pattern", "--region", region, "--event-pattern", json.dumps(patterns[rule]), "--event", json.dumps(event), "--output", "json"]
        result = subprocess.run(command, capture_output=True, text=True, timeout=30, check=True)
        matched = json.loads(result.stdout)["Result"]
        if matched != expected:
            raise RuntimeError(f"Unexpected result for {name}: expected {expected}, got {matched}")
        results.append({"case": name, "expected_match": expected, "actual_match": matched, "passed": True})
        print(f"PASS {name}", flush=True)
    root = Path(__file__).resolve().parents[1]
    sources = [root / "terraform/environments/dev/detection.tf", Path(__file__).resolve()]
    report = {"verified_at_utc": datetime.now(timezone.utc).isoformat(), "method": "AWS EventBridge TestEventPattern API with synthetic fixtures",
              "infrastructure_applied": False, "events_published": False, "end_to_end_delivery_tested": False,
              "source_sha256": {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, "checks": results}
    args.report.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()

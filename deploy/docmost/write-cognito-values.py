#!/usr/bin/env python3
"""Write local Docmost Helm values from non-secret Terraform outputs."""

import json
import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "deploy/docmost/values.local.yaml"
TF_OUTPUT_KEYS = {
    "userPoolArn": "docmost_cognito_user_pool_arn",
    "userPoolClientId": "docmost_cognito_client_id",
    "userPoolDomain": "docmost_cognito_domain_prefix",
}


def main() -> None:
    raw = subprocess.check_output(
        ["terraform", "-chdir=terraform/platform", "output", "-json"],
        cwd=ROOT,
    )
    outputs = json.loads(raw)
    values = {key: outputs[output_key]["value"] for key, output_key in TF_OUTPUT_KEYS.items()}
    content = "ingress:\n  cognito:\n" + "".join(
        f"    {key}: {json.dumps(value)}\n" for key, value in values.items()
    )
    descriptor = os.open(OUTPUT, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        stream.write(content)


if __name__ == "__main__":
    main()

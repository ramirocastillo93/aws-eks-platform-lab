#!/usr/bin/env python3
"""Bind a reviewed PR plan to the configuration and plan applied after merge."""

import argparse
import hashlib
import io
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path


def tree_sha():
    return subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], text=True
    ).strip()


def plan_fingerprint(path):
    raw = subprocess.check_output(["terraform", "show", "-json", path])
    plan = json.loads(raw)
    # This is a run timestamp; changes to the configuration, state or actions remain.
    plan.pop("timestamp", None)
    canonical = json.dumps(plan, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(canonical).hexdigest()


def backend_fingerprint():
    backend = "\0".join(
        (os.environ["AWS_REGION"], os.environ["TF_STATE_BUCKET"], "platform/terraform.tfstate")
    )
    return hashlib.sha256(backend.encode()).hexdigest()


def write_metadata(path):
    metadata = {
        "schema": 1,
        "pr": int(os.environ["PR_NUMBER"]),
        "head_sha": os.environ["PR_HEAD_SHA"],
        "tree_sha": tree_sha(),
        "run_id": int(os.environ["GITHUB_RUN_ID"]),
        "run_attempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
        "plan_fingerprint": plan_fingerprint(path),
        "backend_fingerprint": backend_fingerprint(),
    }
    Path("plan-review.json").write_text(json.dumps(metadata, sort_keys=True) + "\n")
    print("Saved the plan fingerprint and source tree for merge verification.")


def github_get(path, *, binary=False):
    token = os.environ["GH_TOKEN"]
    request = urllib.request.Request(
        os.environ.get("GITHUB_API_URL", "https://api.github.com") + path,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read()
    return body if binary else json.loads(body)


def find_review():
    repository = os.environ["GITHUB_REPOSITORY"]
    pr = int(os.environ["PR_NUMBER"])
    head_sha = os.environ["PR_HEAD_SHA"]
    expected_tree = tree_sha()
    name = f"terraform-plan-pr-{pr}-{head_sha}"
    base = f"/repos/{repository}"
    artifacts = []
    page = 1
    while True:
        query = urllib.parse.urlencode({"name": name, "per_page": 100, "page": page})
        batch = github_get(f"{base}/actions/artifacts?{query}")["artifacts"]
        artifacts.extend(batch)
        if len(batch) < 100:
            break
        page += 1

    for artifact in sorted(artifacts, key=lambda item: item["created_at"], reverse=True):
        if artifact["expired"] or artifact["name"] != name:
            continue
        run_id = artifact["workflow_run"]["id"]
        run = github_get(f"{base}/actions/runs/{run_id}")
        if (
            run["conclusion"] != "success"
            or run["event"] != "pull_request"
            or run["path"].split("@")[0] != ".github/workflows/terraform.yml"
        ):
            continue

        archive = github_get(
            f"{base}/actions/artifacts/{artifact['id']}/zip", binary=True
        )
        if len(archive) > 65536:
            raise ValueError("Plan review artifact is unexpectedly large")
        with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
            if bundle.namelist() != ["plan-review.json"]:
                raise ValueError("Unexpected plan review artifact contents")
            metadata = json.loads(bundle.read("plan-review.json"))
        if (
            metadata.get("schema") == 1
            and metadata.get("pr") == pr
            and metadata.get("head_sha") == head_sha
            and metadata.get("tree_sha") == expected_tree
            and metadata.get("run_id") == run_id
            and metadata.get("run_attempt") == run["run_attempt"]
        ):
            Path("reviewed-plan.json").write_text(
                json.dumps(metadata, sort_keys=True) + "\n"
            )
            print("Found a successful PR plan for the exact merged source tree.")
            return
    raise ValueError("No successful PR plan matches the merged source tree")


def verify_plan(path):
    metadata = json.loads(Path("reviewed-plan.json").read_text())
    if metadata["tree_sha"] != tree_sha():
        raise ValueError("The checked-out source tree differs from the reviewed PR")
    if metadata["plan_fingerprint"] != plan_fingerprint(path):
        raise ValueError("The post-merge plan differs from the reviewed PR plan")
    if metadata["backend_fingerprint"] != backend_fingerprint():
        raise ValueError("The Terraform backend differs from the reviewed PR")
    print("Post-merge plan matches the reviewed PR plan.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["record", "fetch", "verify"])
    parser.add_argument("plan", nargs="?")
    args = parser.parse_args()
    if args.command in ("record", "verify") and not args.plan:
        parser.error("record and verify require a plan file")
    if args.command == "record":
        write_metadata(args.plan)
    elif args.command == "fetch":
        find_review()
    else:
        verify_plan(args.plan)


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Plan review failed: {error}", file=sys.stderr)
        sys.exit(1)

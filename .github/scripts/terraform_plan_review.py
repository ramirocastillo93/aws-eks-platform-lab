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


PLAN_SECTIONS = (
    "resource_changes",
    "output_changes",
    "deferred_changes",
    "checks",
)


def _canonical_value(value):
    """Sort object keys but preserve nested list order and action ordering."""
    if isinstance(value, dict):
        return {key: _canonical_value(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_canonical_value(item) for item in value]
    return value


def plan_fingerprints_from_json(plan):
    """Hash Terraform's planned actions, including sensitive planned values.

    The raw values never enter logs or review metadata; only section digests do.
    Refresh-only drift and no-op entries are not applied and may differ between
    the PR and merge runs, so they are deliberately excluded.
    """
    fingerprints = {}
    for section in PLAN_SECTIONS:
        value = plan.get(section, [] if section != "output_changes" else {})
        if section == "resource_changes":
            value = [
                item for item in value
                if item["change"]["actions"] != ["no-op"]
            ]
        elif section == "output_changes":
            value = {
                name: change for name, change in value.items()
                if change["actions"] != ["no-op"]
            }
        value = _canonical_value(value)
        # These sections are collections whose element ordering is incidental.
        # Preserve nested arrays because Terraform uses action/list order to
        # represent meaningful plan details such as delete-before-create.
        if isinstance(value, list):
            value = sorted(
                value,
                key=lambda item: json.dumps(item, sort_keys=True, separators=(",", ":")),
            )
        canonical = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
        fingerprints[section] = hashlib.sha256(canonical).hexdigest()
    return fingerprints


def plan_fingerprints(path):
    raw = subprocess.check_output(["terraform", "show", "-json", path])
    plan = json.loads(raw)
    return plan_fingerprints_from_json(plan)


def backend_fingerprint():
    backend = "\0".join(
        (os.environ["AWS_REGION"], os.environ["TF_STATE_BUCKET"], "platform/terraform.tfstate")
    )
    return hashlib.sha256(backend.encode()).hexdigest()


def write_metadata(path):
    metadata = {
        "schema": 3,
        "pr": int(os.environ["PR_NUMBER"]),
        "head_sha": os.environ["PR_HEAD_SHA"],
        "tree_sha": tree_sha(),
        "run_id": int(os.environ["GITHUB_RUN_ID"]),
        "run_attempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
        "plan_fingerprints": plan_fingerprints(path),
        "backend_fingerprint": backend_fingerprint(),
    }
    Path("plan-review.json").write_text(json.dumps(metadata, sort_keys=True) + "\n")
    print("Saved the plan fingerprint and source tree for merge verification.")


class GitHubRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        redirected = super().redirect_request(request, fp, code, msg, headers, newurl)
        source = urllib.parse.urlparse(request.full_url)
        destination = urllib.parse.urlparse(newurl)
        if redirected and (destination.scheme, destination.netloc) != (
            source.scheme,
            source.netloc,
        ):
            redirected.remove_header("Authorization")
        return redirected


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
    opener = urllib.request.build_opener(GitHubRedirectHandler())
    with opener.open(request, timeout=30) as response:
        body = response.read()
    return body if binary else json.loads(body)


def find_review():
    repository = os.environ["GITHUB_REPOSITORY"]
    merge_sha = os.environ["GITHUB_SHA"]
    base = f"/repos/{repository}"
    associated_prs = github_get(f"{base}/commits/{merge_sha}/pulls")
    merged_prs = [
        item
        for item in associated_prs
        if item.get("merged_at")
        and item.get("merge_commit_sha") == merge_sha
        and item["base"]["ref"] == "main"
        and item["base"]["repo"]["full_name"] == repository
        and item["head"]["repo"]["full_name"] == repository
    ]
    if len(merged_prs) != 1:
        raise ValueError("Main commit is not the merge of one same-repository PR")
    pr = merged_prs[0]["number"]
    head_sha = merged_prs[0]["head"]["sha"]
    expected_tree = tree_sha()
    name = f"terraform-plan-pr-{pr}-{head_sha}"
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
            metadata.get("schema") == 3
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
    if metadata.get("schema") != 3:
        raise ValueError("The reviewed plan uses an outdated fingerprint format; create a new PR plan")
    if metadata["tree_sha"] != tree_sha():
        raise ValueError("The checked-out source tree differs from the reviewed PR")
    if metadata["backend_fingerprint"] != backend_fingerprint():
        raise ValueError("The Terraform backend differs from the reviewed PR")
    reviewed = metadata["plan_fingerprints"]
    current = plan_fingerprints(path)
    changed = [section for section in PLAN_SECTIONS if reviewed.get(section) != current[section]]
    if changed:
        raise ValueError(
            "The post-merge plan differs in reviewed Terraform sections: "
            + ", ".join(changed)
        )
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

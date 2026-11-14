"""Validate a release event before exposing signing credentials to its job."""

import os
import re
import subprocess
from pathlib import Path


def release_metadata(root, event, ref):
    if event == "workflow_dispatch" and ref != "refs/heads/main":
        raise ValueError("Manual releases must use main")
    version_line = re.search(
        r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$",
        (root / "flutter/pubspec.yaml").read_text(),
        re.MULTILINE,
    )
    if not version_line:
        raise ValueError("pubspec.yaml needs version: major.minor.patch+build")
    version, build = version_line.groups()
    if ref.startswith("refs/tags/"):
        if ref != "refs/tags/v" + version:
            raise ValueError("Release tag must be v<pubspec version>")
    elif ref != "refs/heads/main":
        raise ValueError("Only main or a version tag can publish TestFlight builds")
    if event not in ("push", "workflow_dispatch"):
        raise ValueError("Unsupported release event")
    subprocess.run(
        ["git", "merge-base", "--is-ancestor", "HEAD", "origin/main"],
        cwd=root,
        check=True,
    )
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    return {"sha": sha, "version": version, "base_build": build}


if __name__ == "__main__":
    result = release_metadata(
        Path.cwd(), os.environ["GITHUB_EVENT_NAME"], os.environ["GITHUB_REF"]
    )
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        for key, value in result.items():
            output.write(f"{key}={value}\n")
    print(f"Validated {result['version']} from {result['sha']}")

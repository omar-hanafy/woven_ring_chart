#!/usr/bin/env python3
"""Wait for the exact protected-lane push checks before spending a release tag."""

import argparse
import json
import subprocess
import sys
import time


WORKFLOWS = ("ci.yml", "publish-dry-run.yml")


def check_state(runs, sha, branch):
    matches = [
        run for run in runs
        if run["headSha"] == sha and run["headBranch"] == branch
        and run["event"] == "push"
    ]
    if not matches:
        return "waiting"
    latest = max(matches, key=lambda run: (run["createdAt"], run["databaseId"]))
    if latest["status"] != "completed":
        return "waiting"
    if latest["conclusion"] != "success":
        raise ValueError(
            f"Run {latest['databaseId']} finished with {latest['conclusion']}"
        )
    return "success"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--timeout-seconds", type=int, default=3600)
    args = parser.parse_args()
    deadline = time.monotonic() + args.timeout_seconds
    reported = set()
    while True:
        pending = set()
        for workflow in WORKFLOWS:
            result = subprocess.run(
                [
                    "gh", "run", "list", "--repo", args.repo,
                    "--workflow", workflow, "--commit", args.sha,
                    "--branch", args.branch, "--event", "push", "--limit", "100",
                    "--json",
                    "databaseId,status,conclusion,headSha,headBranch,event,createdAt",
                ],
                capture_output=True, text=True, check=True, timeout=60,
            )
            if check_state(json.loads(result.stdout), args.sha, args.branch) == "success":
                if workflow not in reported:
                    print(f"{workflow} passed on {args.sha}", flush=True)
                    reported.add(workflow)
            else:
                pending.add(workflow)
        if not pending:
            return
        if time.monotonic() >= deadline:
            raise ValueError(f"Timed out waiting for {', '.join(sorted(pending))}")
        time.sleep(min(15, max(0, deadline - time.monotonic())))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""Require the demonstrated version on pub.dev before deploying the showcase."""

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from release_guard import parse_version


PACKAGE = "woven_ring_chart"


def fetch_version(version, timeout):
    """Return availability, retrying only absent or transient responses."""
    url = (
        f"https://pub.dev/api/packages/{PACKAGE}/versions/"
        f"{urllib.parse.quote(version, safe='')}"
    )
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            data = json.load(response)
    except urllib.error.HTTPError as error:
        if error.code in (404, 408, 429) or 500 <= error.code <= 599:
            return False
        raise ValueError(f"pub.dev returned HTTP {error.code} for {PACKAGE} {version}") from error
    except (urllib.error.URLError, TimeoutError):
        return False
    if (
        not isinstance(data, dict)
        or data.get("version") != version
        or not isinstance(data.get("pubspec"), dict)
        or data["pubspec"].get("name") != PACKAGE
        or data["pubspec"].get("version") != version
    ):
        raise ValueError(f"pub.dev response does not identify {PACKAGE} {version}")
    return True


def wait_for_version(version, timeout_seconds=7200):
    parse_version(version)
    if timeout_seconds <= 0:
        raise ValueError("Publication timeout must be positive")
    deadline = time.monotonic() + timeout_seconds
    print(f"Waiting for {PACKAGE} {version} on pub.dev", flush=True)
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError(f"Timed out waiting for {PACKAGE} {version} on pub.dev")
        if fetch_version(version, timeout=min(30, remaining)):
            print(f"Verified {PACKAGE} {version} on pub.dev", flush=True)
            return
        time.sleep(min(15, max(0, deadline - time.monotonic())))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--timeout-seconds", type=int, default=7200)
    args = parser.parse_args()
    wait_for_version(args.version, args.timeout_seconds)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)

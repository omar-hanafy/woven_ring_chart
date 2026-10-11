#!/usr/bin/env python3
"""Validate package metadata and lane before creating an immutable release tag."""

import argparse
import pathlib
import re
import subprocess
import sys


SEMVER = re.compile(
    r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
)


def read_field(pubspec, field):
    matches = re.findall(rf"^{field}:[ \t]*([^\n]*)$", pubspec, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError(f"pubspec.yaml must have exactly one {field}")
    value = matches[0].split("#", 1)[0].strip()
    if value.startswith(("\"", "'")):
        if len(value) < 2 or value[-1] != value[0]:
            raise ValueError(f"pubspec.yaml has invalid quoting for {field}")
        value = value[1:-1]
    if not value:
        raise ValueError(f"pubspec.yaml has no {field}")
    return value


def read_version(pubspec):
    return read_field(pubspec, "version")


def validate_package(pubspec):
    if read_field(pubspec, "name") != "woven_ring_chart":
        raise ValueError("Release package must be named woven_ring_chart")
    return read_version(pubspec)


def parse_version(version):
    match = SEMVER.fullmatch(version)
    if not match:
        raise ValueError(f"Invalid semantic version: {version}")
    prerelease = match.group(4)
    if prerelease and any(
        part.isdigit() and len(part) > 1 and part.startswith("0")
        for part in prerelease.split(".")
    ):
        raise ValueError("Numeric prerelease identifiers cannot have leading zeros")
    return tuple(int(match.group(i)) for i in (1, 2, 3)), prerelease


def compare_versions(left, right):
    left_core, left_pre = parse_version(left)
    right_core, right_pre = parse_version(right)
    if left_core != right_core:
        return 1 if left_core > right_core else -1
    if left_pre == right_pre:
        return 0
    if left_pre is None:
        return 1
    if right_pre is None:
        return -1
    left_parts, right_parts = left_pre.split("."), right_pre.split(".")
    for first, second in zip(left_parts, right_parts):
        if first == second:
            continue
        if first.isdigit() and second.isdigit():
            return 1 if int(first) > int(second) else -1
        if first.isdigit() != second.isdigit():
            return -1 if first.isdigit() else 1
        return 1 if first > second else -1
    return 1 if len(left_parts) > len(right_parts) else -1


def validate(version, lane, changelog):
    _, prerelease = parse_version(version)
    if lane == "main" and prerelease:
        raise ValueError(f"main requires a stable version, got {version}")
    if lane == "dev" and not prerelease:
        raise ValueError(f"dev requires a prerelease version, got {version}")
    release_notes(version, changelog)


def release_notes(version, changelog):
    heading = re.compile(rf"^\[?{re.escape(version)}\]?(?:\s+-.*)?$")
    sections = list(re.finditer(r"^##[ \t]+(.+)$", changelog, re.MULTILINE))
    matches = [section for section in sections if heading.fullmatch(section.group(1))]
    if len(matches) != 1 or not sections or matches[0] != sections[0]:
        raise ValueError(f"CHANGELOG.md must start with exactly one section for {version}")
    end = sections[1].start() if len(sections) > 1 else len(changelog)
    content = re.sub(r"<!--.*?-->", "", changelog[sections[0].end():end], flags=re.DOTALL)
    if not any(line.strip() and not line.lstrip().startswith("#") for line in content.splitlines()):
        raise ValueError(f"CHANGELOG.md section for {version} is empty")
    return content.strip() + "\n"


def release_outputs(version, previous, before):
    if not before or not re.fullmatch(r"[0-9a-fA-F]{40}", before):
        raise ValueError("A full previous GitHub commit SHA is required")
    if set(before) == {"0"}:
        return "changed=false\n"
    if previous == version:
        return "changed=false\n"
    if previous is None or compare_versions(version, previous) <= 0:
        raise ValueError(f"Release version {version} must be newer than {previous}")
    return f"changed=true\nvalue={version}\ntag=woven_ring_chart-v{version}\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lane", required=True)
    parser.add_argument("--before")
    parser.add_argument("--github-output", type=pathlib.Path)
    parser.add_argument("--notes-path", type=pathlib.Path)
    args = parser.parse_args()
    version = validate_package(pathlib.Path("pubspec.yaml").read_text())
    validate(version, args.lane, pathlib.Path("CHANGELOG.md").read_text())
    if args.github_output:
        if not args.before or not re.fullmatch(r"[0-9a-fA-F]{40}", args.before):
            raise ValueError("A full previous GitHub commit SHA is required")
        previous = None
        if set(args.before) != {"0"}:
            result = subprocess.run(
                ["git", "show", f"{args.before}:pubspec.yaml"],
                capture_output=True, text=True, check=False,
            )
            if result.returncode:
                # An unavailable prior commit must not spend a release tag.
                raise ValueError("Cannot read pubspec.yaml at the previous commit")
            previous = validate_package(result.stdout)
        outputs = release_outputs(version, previous, args.before)
        with args.github_output.open("a") as output:
            output.write(outputs)
    if args.notes_path:
        args.notes_path.write_text(release_notes(version, pathlib.Path("CHANGELOG.md").read_text()))
    print(f"Validated {version} for {args.lane}")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(error, file=sys.stderr)
        sys.exit(1)

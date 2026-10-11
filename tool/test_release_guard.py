"""Regression checks for release decisions; no credentials or network needed."""

import pathlib
import subprocess
import sys
import tempfile
import unittest

from release_guard import (compare_versions, read_version, release_notes, release_outputs,
                           validate, validate_package)


class ReleaseGuardTest(unittest.TestCase):
    def test_notes_contain_only_the_validated_current_body(self):
        body = "### Changed\n\n- Raise the minimum SDK.\n\n### Fixed\n\n- Fix winding."
        changelog = f"# Changelog\n\n## [2.0.0] - 2026-10-11\n\n{body}\n\n## [1.0.2]\n\nHistorical.\n"
        self.assertEqual(release_notes("2.0.0", changelog), body + "\n")

    def test_identity_and_unique_version(self):
        self.assertEqual(
            validate_package("name: woven_ring_chart\nversion: 1.2.3\n"), "1.2.3"
        )
        for pubspec in [
            "name: another_package\nversion: 1.2.3\n",
            "name: woven_ring_chart\nversion: 1.2.3\nversion: 1.2.4\n",
            "name: woven_ring_chart\nversion: 1.2.3\nversion:\n",
            "name: woven_ring_chart\nversion: \"1.2.3'\n",
            "name: woven_ring_chart\nname: another_package\nversion: 1.2.3\n",
        ]:
            with self.subTest(pubspec=pubspec):
                with self.assertRaises(ValueError):
                    validate_package(pubspec)

    def test_top_changelog_section_is_unique_and_nonempty(self):
        for changelog in [
            "## [1.2.3]\n\n### Changed\n",
            "## [1.2.3]\n\n<!-- pending -->\n",
            "## [1.2.4]\nNewer.\n## [1.2.3]\nOlder.\n",
            "## [1.2.3]\nNew.\n## [1.2.3]\nDuplicate.\n",
        ]:
            with self.subTest(changelog=changelog):
                with self.assertRaises(ValueError):
                    validate("1.2.3", "main", changelog)

    def test_semver_precedence_and_monotonic_releases(self):
        ordered = [
            "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
            "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1",
        ]
        for earlier, later in zip(ordered, ordered[1:]):
            self.assertLess(compare_versions(earlier, later), 0)
            self.assertGreater(compare_versions(later, earlier), 0)
            self.assertTrue(release_outputs(later, earlier, "a" * 40).startswith("changed=true"))
        self.assertEqual(compare_versions("1.0.0+a", "1.0.0+b"), 0)
        for current, previous in [("1.5.0", "2.0.0"), ("1.0.0+a", "1.0.0+b")]:
            with self.subTest(current=current, previous=previous):
                with self.assertRaises(ValueError):
                    release_outputs(current, previous, "a" * 40)

    def test_release_requires_a_full_previous_sha(self):
        for before in [None, "", "abc", "--help", "z" * 40]:
            with self.subTest(before=before):
                with self.assertRaises(ValueError):
                    release_outputs("1.0.3", "1.0.2", before)

    def test_version_only_changes_trigger_release(self):
        self.assertEqual(
            release_outputs("1.0.2", "1.0.2", "a" * 40), "changed=false\n"
        )
        self.assertEqual(
            release_outputs("1.0.3", "1.0.2", "a" * 40),
            "changed=true\nvalue=1.0.3\ntag=woven_ring_chart-v1.0.3\n",
        )
        self.assertEqual(
            release_outputs("1.0.3", None, "0" * 40), "changed=false\n"
        )

    def test_yaml_version_quotes_and_comments(self):
        self.assertEqual(read_version('version: "1.2.3" # release\n'), "1.2.3")
        with self.assertRaises(ValueError):
            read_version("name: woven_ring_chart\n")

    def test_lane_and_changelog(self):
        validate("1.2.3", "main", "## [1.2.3] - 2026-10-11\n\nFixed an issue.\n")
        validate("1.2.3-dev.1", "dev", "## 1.2.3-dev.1\n\nAdded a feature.\n")
        for version, lane in [("1.2.3-dev.1", "main"), ("1.2.3", "dev")]:
            with self.subTest(version=version, lane=lane):
                with self.assertRaises(ValueError):
                    validate(version, lane, f"## [{version}]\n")
        with self.assertRaises(ValueError):
            validate("1.2.3", "main", "## [1.2.30]\n")

    def test_rejects_invalid_versions_before_tag_output(self):
        for version in [
            "01.2.3", "1.2", "1.2.3-", "1.2.3-a..b", "1.2.3-dev.01",
            "1.2.3+", "1.2.3\nchanged=true", "1.2.3/other",
        ]:
            with self.subTest(version=version):
                with self.assertRaises(ValueError):
                    validate(version, "dev", f"## [{version}]\n")

    def test_missing_previous_commit_fails_without_release_output(self):
        script = pathlib.Path(__file__).with_name("release_guard.py").resolve()
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "pubspec.yaml").write_text("name: woven_ring_chart\nversion: 1.2.3\n")
            (root / "CHANGELOG.md").write_text("## [1.2.3]\n\nFixed an issue.\n")
            subprocess.run(["git", "init", "--quiet", directory], check=True)
            output = root / "output"
            for before in [None, "a" * 40]:
                command = [
                    sys.executable, str(script), "--lane", "main",
                    "--github-output", str(output),
                ]
                if before:
                    command.extend(["--before", before])
                result = subprocess.run(
                    command, cwd=root, capture_output=True, text=True, check=False
                )
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()

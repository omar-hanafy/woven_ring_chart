"""Ensure only successful checks on the requested branch push can release."""

import unittest

from wait_release_checks import check_state


def run(**changes):
    record = dict(
        databaseId=1, status="completed", conclusion="success", headSha="sha",
        headBranch="main", event="push", createdAt="2026-10-11T00:00:00Z",
    )
    record.update(changes)
    return record


class WaitReleaseChecksTest(unittest.TestCase):
    def test_matching_completed_success_is_required(self):
        self.assertEqual(check_state([run()], "sha", "main"), "success")
        for runs in [
            [], [run(headSha="old")], [run(headBranch="dev")],
            [run(event="pull_request")], [run(status="in_progress", conclusion=None)],
        ]:
            with self.subTest(runs=runs):
                self.assertEqual(check_state(runs, "sha", "main"), "waiting")

    def test_failed_cancelled_skipped_and_timed_out_checks_block(self):
        for conclusion in ["failure", "cancelled", "skipped", "timed_out", None]:
            with self.subTest(conclusion=conclusion):
                with self.assertRaises(ValueError):
                    check_state([run(conclusion=conclusion)], "sha", "main")

    def test_latest_run_controls_release(self):
        previous = run()
        latest = run(databaseId=2, createdAt="2026-10-11T00:01:00Z")
        self.assertEqual(check_state([previous, latest], "sha", "main"), "success")
        with self.assertRaises(ValueError):
            check_state([previous, run(databaseId=2, conclusion="failure")], "sha", "main")
        self.assertEqual(
            check_state([previous, run(databaseId=2, status="queued")], "sha", "main"),
            "waiting",
        )


if __name__ == "__main__":
    unittest.main()

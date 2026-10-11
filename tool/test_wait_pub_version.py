"""Verify that Pages requires the exact published package without real waits."""

import io
import json
import unittest
import urllib.error
from unittest import mock

from wait_pub_version import fetch_version, wait_for_version


def response(**changes):
    data = dict(
        version="2.0.0", pubspec=dict(name="woven_ring_chart", version="2.0.0"),
    )
    data.update(changes)
    return io.BytesIO(json.dumps(data).encode())


class WaitPubVersionTest(unittest.TestCase):
    @mock.patch("wait_pub_version.urllib.request.urlopen")
    def test_exact_version_request_and_success(self, urlopen):
        urlopen.return_value = response()
        self.assertTrue(fetch_version("2.0.0", 7))
        urlopen.assert_called_once_with(
            "https://pub.dev/api/packages/woven_ring_chart/versions/2.0.0", timeout=7,
        )

    @mock.patch("wait_pub_version.urllib.request.urlopen")
    def test_mismatched_or_malformed_identity_blocks(self, urlopen):
        for data in [
            response(version="1.0.2"), response(pubspec=dict(name="another", version="2.0.0")),
            response(pubspec=dict(name="woven_ring_chart", version="1.0.2")),
            response(pubspec=None), io.BytesIO(b"[]"), io.BytesIO(b"not json"),
        ]:
            with self.subTest(data=data.getvalue()):
                urlopen.return_value = data
                with self.assertRaises(ValueError):
                    fetch_version("2.0.0", 30)

    @mock.patch("wait_pub_version.urllib.request.urlopen")
    def test_absent_and_transient_http_responses_retry(self, urlopen):
        for status in [404, 408, 429, 500, 502, 503, 599]:
            with self.subTest(status=status):
                urlopen.side_effect = urllib.error.HTTPError("url", status, "error", {}, None)
                self.assertFalse(fetch_version("2.0.0", 30))

    @mock.patch("wait_pub_version.urllib.request.urlopen")
    def test_other_http_failures_block(self, urlopen):
        for status in [400, 401, 403, 410]:
            with self.subTest(status=status):
                urlopen.side_effect = urllib.error.HTTPError("url", status, "error", {}, None)
                with self.assertRaisesRegex(ValueError, f"HTTP {status}"):
                    fetch_version("2.0.0", 30)

    @mock.patch("wait_pub_version.urllib.request.urlopen")
    def test_network_timeouts_retry(self, urlopen):
        for error in [urllib.error.URLError("temporary connection failure"), TimeoutError()]:
            with self.subTest(error=error):
                urlopen.side_effect = error
                self.assertFalse(fetch_version("2.0.0", 30))

    @mock.patch("wait_pub_version.time.sleep")
    @mock.patch("wait_pub_version.time.monotonic", return_value=0)
    @mock.patch("wait_pub_version.urllib.request.urlopen")
    def test_404_then_publication_succeeds(self, urlopen, monotonic, sleep):
        urlopen.side_effect = [
            urllib.error.HTTPError("url", 404, "not published", {}, None), response(),
        ]
        wait_for_version("2.0.0", 60)
        self.assertEqual(urlopen.call_count, 2)
        sleep.assert_called_once_with(15)

    @mock.patch("wait_pub_version.time.sleep")
    @mock.patch("wait_pub_version.time.monotonic", return_value=0)
    @mock.patch("wait_pub_version.urllib.request.urlopen")
    def test_already_published_version_succeeds_without_wait(self, urlopen, monotonic, sleep):
        urlopen.return_value = response()
        wait_for_version("2.0.0", 60)
        sleep.assert_not_called()

    @mock.patch("wait_pub_version.time.sleep")
    @mock.patch("wait_pub_version.time.monotonic", side_effect=[0, 0, 7, 7])
    @mock.patch("wait_pub_version.fetch_version", return_value=False)
    def test_timeout_bounds_request_and_sleep(self, fetch, monotonic, sleep):
        with self.assertRaisesRegex(ValueError, "Timed out waiting"):
            wait_for_version("2.0.0", 7)
        fetch.assert_called_once_with("2.0.0", timeout=7)
        sleep.assert_called_once_with(0)

    @mock.patch("wait_pub_version.fetch_version")
    def test_invalid_version_and_timeout_do_not_request_pub(self, fetch):
        for version, timeout in [("latest", 60), ("2.0.0", 0), ("2.0.0", -1)]:
            with self.subTest(version=version, timeout=timeout):
                with self.assertRaises(ValueError):
                    wait_for_version(version, timeout)
        fetch.assert_not_called()


if __name__ == "__main__":
    unittest.main()

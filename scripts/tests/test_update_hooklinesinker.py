import contextlib
import hashlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError, URLError


SCRIPT = Path(__file__).resolve().parents[1] / "update_hooklinesinker.py"
SPEC = importlib.util.spec_from_file_location("update_hooklinesinker", SCRIPT)
updater = importlib.util.module_from_spec(SPEC)
with patch.object(sys, "path", [str(SCRIPT.parent), *sys.path]):
    SPEC.loader.exec_module(updater)


class HooklinesinkerUpdateTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "scripts").mkdir()
        self.pin_path = self.root / "scripts/hooklinesinker.json"
        self.remote_path = self.root / "scripts/install-remote.sh"
        self.pin = {"version": "1.0.1", "protocol": 1, "sourceRevision": "a" * 40}
        self.pin_path.write_text(json.dumps(self.pin, indent=2) + "\n")
        self.remote_path.write_text(
            '#!/bin/bash\nREVISION="${JUGGLER_REVISION:-' + "b" * 40 + '}"\n'
            'HLS_VERSION="${HOOKLINESINKER_VERSION:-v1.0.1}"\n'
        )
        self.remote_path.chmod(0o755)
        self.originals = {path: path.read_bytes() for path in (self.pin_path, self.remote_path)}
        self.release = {
            "tag_name": "v1.1.0", "draft": False, "prerelease": False,
            "assets": [{"name": updater.hls.ARTIFACT}, {"name": "SHA256SUMS"}],
        }
        self.binary_version = {"version": "1.1.0", "protocol": 1}
        self.architectures = "arm64 x86_64"
        self.bad_checksum = False
        self.queries = []
        self.executions = []
        self.start_patch(patch.object(updater, "ROOT", self.root))
        self.start_patch(patch.object(updater, "urlopen", side_effect=self.release_response))
        self.start_patch(patch.object(updater.hls, "download", side_effect=self.download))
        self.start_patch(patch.object(updater.hls, "run", side_effect=self.command))
        self.start_patch(patch.dict(os.environ, {"GITHUB_ACTIONS": "false"}))

    def start_patch(self, patcher):
        result = patcher.start()
        self.addCleanup(patcher.stop)
        return result

    def release_response(self, request, **kwargs):
        self.queries.append(request.full_url)
        return io.BytesIO(json.dumps(self.release).encode())

    def download(self, pin, output):
        binary = output / updater.hls.ARTIFACT
        binary.write_bytes(b"verified release binary")
        digest = "0" * 64 if self.bad_checksum else hashlib.sha256(binary.read_bytes()).hexdigest()
        (output / "SHA256SUMS").write_text(f"{digest}  {updater.hls.ARTIFACT}\n")

    def command(self, *arguments, **kwargs):
        if arguments[:2] == ("git", "ls-remote"):
            ref = "refs/tags/" + self.release["tag_name"]
            return f"{'c' * 40}\t{ref}\n{'d' * 40}\t{ref}^{{}}\n"
        if arguments[:2] == ("lipo", "-archs"):
            return self.architectures
        if arguments[1:] == ("version", "--json"):
            self.executions.append(arguments)
            return json.dumps(self.binary_version)
        raise AssertionError(f"Unexpected command: {arguments}")

    def invoke(self, *arguments):
        with patch.object(sys, "argv", [str(SCRIPT), *arguments]), \
                contextlib.redirect_stdout(io.StringIO()) as stdout, \
                contextlib.redirect_stderr(io.StringIO()) as stderr:
            updater.main()
        return stdout.getvalue(), stderr.getvalue()

    def assert_pins_preserved(self):
        self.assertEqual({path: path.read_bytes() for path in self.originals}, self.originals)

    def test_update_latest_changes_both_pins_and_preserves_installer_revision_and_mode(self):
        stdout, _ = self.invoke()
        self.assertEqual(updater.hls.read_pin(self.root), {
            "version": "1.1.0", "protocol": 1, "sourceRevision": "d" * 40,
        })
        self.assertEqual(self.remote_path.read_bytes(),
                         self.originals[self.remote_path].replace(b"v1.0.1", b"v1.1.0"))
        self.assertEqual(self.remote_path.stat().st_mode & 0o777, 0o755)
        self.assertEqual(self.queries, [f"https://api.github.com/repos/{updater.REPOSITORY}/releases/latest"])
        self.assertIn("Updated HLS 1.0.1 -> 1.1.0", stdout)

    def test_update_accepts_an_explicit_published_version(self):
        self.invoke("v1.1.0")
        self.assertEqual(self.queries, [f"https://api.github.com/repos/{updater.REPOSITORY}/releases/tags/v1.1.0"])
        self.assertEqual(updater.hls.read_pin(self.root)["version"], "1.1.0")

    def test_tag_resolution_handles_lightweight_tags_and_rejects_missing_commits(self):
        with patch.object(updater.hls, "run", return_value=f"{'e' * 40}\trefs/tags/v1.1.0\n"):
            self.assertEqual(updater.release_revision("v1.1.0"), "e" * 40)
        for response in ("", "bad\trefs/tags/v1.1.0", f"{'e' * 40}\trefs/tags/v1.2.0"):
            with self.subTest(response=response), patch.object(updater.hls, "run", return_value=response), \
                    self.assertRaisesRegex(ValueError, "Could not resolve"):
                updater.release_revision("v1.1.0")

    def test_unpublished_release_reports_the_required_workflow_completion(self):
        error = HTTPError("https://api.github.com", 404, "Not Found", {}, None)
        with patch.object(updater, "urlopen", side_effect=error), \
                self.assertRaisesRegex(ValueError, "check that its release workflow completed successfully"):
            updater.update(self.pin)
        self.assert_pins_preserved()

    def test_draft_prerelease_and_mismatched_tag_are_rejected(self):
        original = dict(self.release)
        for fields in ({"draft": True}, {"prerelease": True}, {"tag_name": "v1.1.0-rc.1"},
                       {"tag_name": "v1.2.0"}, {"tag_name": None}):
            with self.subTest(fields=fields), self.assertRaises(ValueError):
                self.release = dict(original, **fields)
                updater.update(self.pin, "1.1.0")
            self.assert_pins_preserved()

    def test_invalid_versions_stop_before_contacting_github(self):
        for version in ("1.02.0", "1.1", "../main", "1.1.0-rc.1"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                updater.published_release(version)
        self.assertEqual(self.queries, [])

    def test_missing_artifacts_and_downgrades_preserve_pins(self):
        for fields in ({"assets": [{"name": "SHA256SUMS"}]}, {"tag_name": "v1.0.0"}):
            with self.subTest(fields=fields), self.assertRaises(ValueError):
                self.release.update(fields)
                updater.update(self.pin)
            self.assert_pins_preserved()

    def test_checksum_failure_preserves_pins_without_executing_the_binary(self):
        self.bad_checksum = True
        with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
            updater.update(self.pin)
        self.assert_pins_preserved()
        self.assertEqual(self.executions, [])

    def test_incompatible_protocol_or_binary_version_preserves_pins(self):
        for version in ({"version": "1.1.0", "protocol": 2}, {"version": "1.0.1", "protocol": 1}):
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, "does not match"):
                self.binary_version = version
                updater.update(self.pin)
            self.assert_pins_preserved()

    def test_thin_release_binary_preserves_pins(self):
        self.architectures = "arm64"
        with self.assertRaisesRegex(ValueError, "Expected arm64 and x86_64"):
            updater.update(self.pin)
        self.assert_pins_preserved()

    def test_current_release_is_a_no_op(self):
        self.release["tag_name"] = "v1.0.1"
        with patch.object(updater, "release_revision", return_value=self.pin["sourceRevision"]):
            stdout, _ = self.invoke()
        self.assertIn("already pinned", stdout)
        self.assert_pins_preserved()

    def test_failed_second_write_restores_the_first_pin(self):
        replace = os.replace

        def fail_remote(source, destination):
            if destination == self.remote_path:
                raise OSError("simulated write failure")
            replace(source, destination)

        with patch.object(os, "replace", side_effect=fail_remote), \
                self.assertRaisesRegex(OSError, "simulated write failure"):
            updater.update(self.pin)
        self.assert_pins_preserved()

    def test_concurrent_installer_edit_is_preserved(self):
        edited = self.originals[self.remote_path] + b"echo user edit\n"

        def download_with_edit(pin, output):
            self.download(pin, output)
            self.remote_path.write_bytes(edited)

        with patch.object(updater.hls, "download", side_effect=download_with_edit), \
                self.assertRaisesRegex(ValueError, "pins changed during"):
            updater.update(self.pin)
        self.assertEqual(self.remote_path.read_bytes(), edited)
        self.assertEqual(self.pin_path.read_bytes(), self.originals[self.pin_path])

    def test_check_warns_about_newer_version_without_changing_pins(self):
        self.release["tag_name"] = "v1.10.0"
        _, stderr = self.invoke("--check")
        self.assertIn("WARNING: HLS 1.10.0 is published; Juggler pins 1.0.1", stderr)
        self.assertIn("just update-hooklinesinker", stderr)
        self.assert_pins_preserved()

    def test_check_reports_current_version(self):
        self.release["tag_name"] = "v1.0.1"
        stdout, _ = self.invoke("--check")
        self.assertIn("HLS pinned: 1.0.1; latest published: 1.0.1.", stdout)
        self.assert_pins_preserved()

    def test_check_handles_network_failure_and_rate_limits_as_warnings(self):
        for error in (URLError("offline"), HTTPError("https://api.github.com", 403, "rate limited", {}, None)):
            with self.subTest(error=error), patch.object(updater, "urlopen", side_effect=error):
                _, stderr = self.invoke("--check")
            self.assertIn("Could not check for HLS updates", stderr)
            self.assertIn("Continuing with 1.0.1", stderr)
            self.assert_pins_preserved()

    def test_ci_check_emits_a_workflow_warning(self):
        with patch.dict(os.environ, {"GITHUB_ACTIONS": "true"}):
            _, stderr = self.invoke("--check")
        self.assertIn("::warning::HLS 1.1.0 is published", stderr)


if __name__ == "__main__":
    unittest.main()

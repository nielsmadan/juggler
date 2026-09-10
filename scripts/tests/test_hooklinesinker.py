import hashlib
import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "hooklinesinker.py"
SPEC = importlib.util.spec_from_file_location("hooklinesinker_packaging", SCRIPT)
hls = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(hls)


class HooklinesinkerPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="juggler helper ")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.artifact = self.directory / hls.ARTIFACT
        self.artifact.write_bytes(b"new helper")
        self.artifact.chmod(0o755)
        self.manifest = self.directory / "SHA256SUMS"
        self.digest = hashlib.sha256(self.artifact.read_bytes()).hexdigest()
        self.manifest.write_text(f"{self.digest}  {hls.ARTIFACT}\n")
        self.output = self.directory / "staged/hooklinesinker"
        self.pin = {"version": "1.0.0", "protocol": 1, "sourceRevision": "a" * 40}

    def test_stages_verified_universal_helper_and_signs_before_embedding(self):
        responses = ["x86_64 arm64", json.dumps(self.pin), "", ""]
        with patch.object(hls, "run", side_effect=responses) as run:
            hls.stage(self.directory, self.output, self.pin)
        self.assertEqual(self.output.read_bytes(), b"new helper")
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o755)
        self.assertEqual(run.call_args_list[2].args[:8],
                         ("codesign", "--force", "--sign", "-", "--identifier", hls.IDENTIFIER,
                          "--options", "runtime"))

    def test_invalid_manifest_or_checksum_stops_before_execution_and_preserves_staged_binary(self):
        self.output.parent.mkdir()
        self.output.write_bytes(b"previous verified helper")
        for contents in ("", f"{self.digest}  unrelated-file\n",
                         self.manifest.read_text() * 2, f"{'0' * 64}  {hls.ARTIFACT}\n"):
            with self.subTest(contents=contents):
                self.manifest.write_text(contents)
                with patch.object(hls, "run") as run, self.assertRaises(ValueError):
                    hls.stage(self.directory, self.output, self.pin)
                run.assert_not_called()
                self.assertEqual(self.output.read_bytes(), b"previous verified helper")

    def test_thin_binary_is_rejected_before_execution(self):
        with patch.object(hls, "run", return_value="arm64") as run:
            with self.assertRaisesRegex(ValueError, "Expected arm64 and x86_64"):
                hls.verify_binary(self.artifact, self.pin)
        run.assert_called_once_with("lipo", "-archs", str(self.artifact))

    def test_development_builds_pinned_source_and_reuses_it_until_revision_changes(self):
        builds = []

        def command(*arguments, **kwargs):
            if arguments[0] == "cargo":
                revision = arguments[arguments.index("--rev") + 1]
                builds.append(revision)
                self.assertIn("--locked", arguments)
                self.assertEqual(arguments[arguments.index("--target") + 1], "aarch64-apple-darwin")
                binary = Path(arguments[arguments.index("--root") + 1]) / "bin/hooklinesinker"
                binary.parent.mkdir(parents=True)
                binary.write_bytes(revision.encode())
            elif arguments[0] == "lipo":
                return "arm64"
            elif arguments[1:] == ("version", "--json"):
                return json.dumps(self.pin)
            return ""

        with patch.object(hls, "ROOT", self.directory), \
                patch.object(hls, "native_target", return_value=("aarch64-apple-darwin", "arm64")), \
                patch.object(hls, "read_pin", return_value=self.pin), \
                patch.object(hls, "run", side_effect=command), \
                patch.dict(os.environ, {}, clear=True), \
                patch.object(sys, "argv", [str(SCRIPT), "stage", "--development", "--output", str(self.output)]):
            hls.main()
            hls.main()
            self.assertEqual(self.output.read_bytes(), self.pin["sourceRevision"].encode())
            self.pin["sourceRevision"] = "b" * 40
            hls.main()
            self.assertEqual(self.output.read_bytes(), b"b" * 40)

        self.assertEqual(builds, ["a" * 40, "b" * 40])

    def test_development_rejects_a_helper_for_another_mac_architecture(self):
        with patch.object(hls, "native_target", return_value=("aarch64-apple-darwin", "arm64")), \
                patch.object(hls, "run", return_value="x86_64") as run, \
                self.assertRaisesRegex(ValueError, "Expected a helper for arm64"):
            hls.verify_binary(self.artifact, self.pin, development=True)
        run.assert_called_once_with("lipo", "-archs", str(self.artifact))

    def test_development_cannot_be_selected_with_release_modes(self):
        for arguments in (["stage", "--published"], ["verify", "Juggler.app", "--distribution"]):
            with self.subTest(arguments=arguments), contextlib.redirect_stderr(io.StringIO()), \
                    patch.object(sys, "argv", [str(SCRIPT), *arguments, "--development"]), \
                    self.assertRaises(SystemExit) as error:
                hls.main()
            self.assertEqual(error.exception.code, 2)

    def test_published_staging_fetches_release_even_with_local_override_and_cache(self):
        cache = self.directory / "build/hooklinesinker/downloads/1.0.0"
        cache.mkdir(parents=True)
        (cache / hls.ARTIFACT).write_bytes(self.artifact.read_bytes())
        (cache / "SHA256SUMS").write_text(self.manifest.read_text())
        published = b"published helper"

        def fetch_release(pin, output):
            (output / hls.ARTIFACT).write_bytes(published)
            digest = hashlib.sha256(published).hexdigest()
            (output / "SHA256SUMS").write_text(f"{digest}  {hls.ARTIFACT}\n")

        with patch.object(hls, "ROOT", self.directory), \
                patch.object(hls, "read_pin", return_value=self.pin), \
                patch.object(hls, "download", side_effect=fetch_release), \
                patch.object(hls, "run", side_effect=["arm64 x86_64", json.dumps(self.pin), "", ""]), \
                patch.dict(os.environ, {"HOOKLINESINKER_DIST": str(self.directory)}), \
                patch.object(sys, "argv", [str(SCRIPT), "stage", "--published", "--output", str(self.output)]):
            hls.main()

        self.assertEqual(self.output.read_bytes(), published)
        self.assertEqual((cache / hls.ARTIFACT).read_bytes(), published)

    def test_version_and_protocol_must_match_the_pin(self):
        for version in ({"version": "0.9.0", "protocol": 1}, {"version": "1.0.0", "protocol": 2}):
            with self.subTest(version=version), patch.object(
                hls, "run", side_effect=["arm64 x86_64", json.dumps(version)]
            ), self.assertRaisesRegex(ValueError, "does not match the pin"):
                hls.verify_binary(self.artifact, self.pin)

    def test_signed_distribution_requires_both_architectures_to_have_the_apps_identity(self):
        good = (f"Identifier={hls.IDENTIFIER}\nflags=0x10000(runtime)\n"
                "Authority=Developer ID Application: Example\nTeamIdentifier=TEAM\nTimestamp=today\n")
        bad_signatures = [good.replace("runtime)", "none)"), good.replace("TEAM", "OTHER"),
                          good.replace("Timestamp=today\n", ""),
                          good.replace("Authority=Developer ID Application: Example\n", "Signature=adhoc\n")]
        for bad in bad_signatures:
            with self.subTest(signature=bad), patch.object(hls, "run", return_value=""), \
                    patch.object(hls, "signature_metadata", side_effect=[good, bad]), \
                    self.assertRaises(ValueError):
                hls.verify_signature(self.artifact, True, "TEAM")

    def test_pin_rejects_remote_installer_drift_and_duplicate_defaults(self):
        scripts = self.directory / "scripts"
        scripts.mkdir()
        (scripts / "hooklinesinker.json").write_text(json.dumps(self.pin))
        remote = scripts / "install-remote.sh"
        remote.write_text('HLS_VERSION="${HOOKLINESINKER_VERSION:-v1.0.0}"\n')
        self.assertEqual(hls.read_pin(self.directory), self.pin)
        for contents in (remote.read_text() * 2, 'HLS_VERSION="${HOOKLINESINKER_VERSION:-v0.9.0}"\n'):
            remote.write_text(contents)
            with self.assertRaisesRegex(ValueError, "version pins differ"):
                hls.read_pin(self.directory)


if __name__ == "__main__":
    unittest.main()

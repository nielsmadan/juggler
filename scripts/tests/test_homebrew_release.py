import hashlib
import importlib.util
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "render-homebrew-cask.py"
SPEC = importlib.util.spec_from_file_location("render_homebrew_cask", SCRIPT)
renderer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(renderer)


class HomebrewReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="juggler release ")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.app = self.directory / "Juggler.app"
        self.resources = self.app / "Contents/Resources"
        self.resources.mkdir(parents=True)
        for name in ("uninstall.sh", "integration_cleanup.py", "codex_config_cleanup.py"):
            (self.resources / name).touch()
        self.info = {"CFBundleShortVersionString": "1.7.3", "CFBundleIdentifier": "com.nielsmadan.Juggler",
                     "LSMinimumSystemVersion": "15.0"}
        self.write_info()
        self.dmg = self.directory / "Juggler.dmg"
        self.dmg.write_bytes(b"release artifact")

    def write_info(self):
        with (self.app / "Contents/Info.plist").open("wb") as file:
            plistlib.dump(self.info, file)

    def test_renders_the_release_artifact_version_checksum_and_os_requirement(self):
        output = self.directory / "juggler.rb"
        result = subprocess.run(["python3", str(SCRIPT), "1.7.3", str(self.app), str(self.dmg), str(output)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        cask = output.read_text()
        self.assertIn('version "1.7.3"', cask)
        self.assertIn(f'sha256 "{hashlib.sha256(self.dmg.read_bytes()).hexdigest()}"', cask)
        self.assertIn('depends_on macos: :sequoia', cask)
        self.assertIn('auto_updates true', cask)
        syntax = subprocess.run(["ruby", "-c", str(output)], capture_output=True, text=True)
        self.assertEqual(syntax.returncode, 0, syntax.stdout + syntax.stderr)

    def test_rejects_the_unreleased_os_fix_and_version_mismatches(self):
        for key, value in (("LSMinimumSystemVersion", "26.2"),
                           ("CFBundleShortVersionString", "1.7.2"),
                           ("CFBundleIdentifier", "another.app")):
            with self.subTest(key=key):
                original = self.info[key]
                self.info[key] = value
                self.write_info()
                with self.assertRaises(ValueError):
                    renderer.render_cask("1.7.3", self.app, self.dmg)
                self.info[key] = original

    def test_rejects_a_bundle_without_the_safe_cleanup_helper(self):
        (self.resources / "integration_cleanup.py").unlink()
        with self.assertRaisesRegex(ValueError, "Missing bundled cleanup resource"):
            renderer.render_cask("1.7.3", self.app, self.dmg)


if __name__ == "__main__":
    unittest.main()

import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class PreparationTests(unittest.TestCase):
    def test_updates_build_versions_and_both_installer_pins(self):
        root = Path(__file__).resolve().parent.parent
        files = [
            "Juggler.xcodeproj/project.pbxproj",
            "juggler/Views/SettingsView.swift",
            "scripts/install-remote.sh",
        ]
        with tempfile.TemporaryDirectory() as temporary:
            checkout = Path(temporary)
            for name in files:
                path = checkout / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((root / name).read_bytes())
            revision = "a1" * 20
            for action, value in [("version", "9.8.7"), ("revision", revision)]:
                subprocess.run(
                    [sys.executable, str(root / "scripts/prepare_release.py"), action, value],
                    cwd=checkout,
                    check=True,
                )
            project = (checkout / files[0]).read_text()
            versions = re.findall(r"MARKETING_VERSION = ([^;]+);", project)
            self.assertTrue(versions)
            self.assertEqual(set(versions), {"9.8.7"})
            self.assertIn(f'installRevision = "{revision}"', (checkout / files[1]).read_text())
            self.assertIn(f"JUGGLER_REVISION:-{revision}", (checkout / files[2]).read_text())


if __name__ == "__main__":
    unittest.main()

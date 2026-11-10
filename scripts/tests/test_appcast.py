import importlib.util
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/update_appcast.py"
SPEC = importlib.util.spec_from_file_location("update_appcast", SCRIPT)
appcast = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(appcast)

LAST_ITEM = re.compile(r"        <item>\n(?:(?!        <item>).)*?        </item>\n(?=    </channel>)", re.DOTALL)


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.published = (ROOT / "appcast.xml").read_text()
        last = LAST_ITEM.search(self.published).group(0)
        self.release = {
            "version": re.search(r"<sparkle:version>([^<]+)<", last).group(1),
            "length": re.search(r'length="([^"]+)"', last).group(1),
            "signature": re.search(r'sparkle:edSignature="([^"]+)"', last).group(1),
            "pub_date": re.search(r"<pubDate>([^<]+)<", last).group(1),
        }
        self.previous = self.published.replace(last, "")

    def test_adds_the_release_in_the_published_feed_format(self):
        self.assertEqual(appcast.add_release(self.previous, **self.release), self.published)

    def test_a_published_release_is_left_unchanged(self):
        self.assertIsNone(appcast.add_release(self.published, **self.release))

    def test_rejects_incomplete_release_details(self):
        for key, value in (("version", "v1.2.3"), ("length", ""), ("signature", "")):
            with self.subTest(key=key):
                with self.assertRaises(ValueError):
                    appcast.add_release(self.previous, **{**self.release, key: value})

    def test_cli_reruns_without_a_duplicate_item(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            path.write_text(self.previous)
            command = ["python3", str(SCRIPT), str(path), self.release["version"], self.release["length"],
                       self.release["signature"], self.release["pub_date"]]
            first = subprocess.run(command, capture_output=True, text=True)
            second = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual((first.returncode, first.stdout), (0, "added\n"), first.stderr)
            self.assertEqual((second.returncode, second.stdout), (0, "present\n"), second.stderr)
            self.assertEqual(path.read_text(), self.published)


if __name__ == "__main__":
    unittest.main()

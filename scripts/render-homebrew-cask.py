import argparse
import hashlib
import os
import plistlib
import re
from pathlib import Path


def render_cask(version, app, dmg):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError(f"Invalid release version: {version}")
    with (app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    if info.get("CFBundleShortVersionString") != version:
        raise ValueError("The app version does not match the release tag")
    if info.get("CFBundleIdentifier") != "com.nielsmadan.Juggler":
        raise ValueError("Unexpected app bundle identifier")
    minimum = info.get("LSMinimumSystemVersion")
    if minimum not in ("15.0", "15.0.0"):
        raise ValueError(f"The app requires macOS {minimum}; the supported minimum is 15.0")
    for name in ("uninstall.sh", "integration_cleanup.py", "codex_config_cleanup.py"):
        if not (app / "Contents/Resources" / name).is_file():
            raise ValueError(f"Missing bundled cleanup resource: {name}")
    helper = app / "Contents/MacOS/hooklinesinker"
    if not helper.is_file() or helper.is_symlink() or not os.access(helper, os.X_OK):
        raise ValueError("Missing executable embedded hooklinesinker")

    digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
    template = Path(__file__).resolve().parents[1] / "homebrew/juggler.rb.in"
    return (template.read_text()
            .replace("@VERSION@", version)
            .replace("@SHA256@", digest))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("app", type=Path)
    parser.add_argument("dmg", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    contents = render_cask(args.version, args.app, args.dmg)
    args.output.write_text(contents)


if __name__ == "__main__":
    main()

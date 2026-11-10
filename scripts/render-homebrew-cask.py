import argparse
import hashlib
import os
import plistlib
import re
from pathlib import Path

RELEASE_VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")
CASK_VERSION = re.compile(r'^  version "([^"]+)"$', re.MULTILINE)


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


def cask_version(content):
    versions = CASK_VERSION.findall(content)
    match = RELEASE_VERSION.fullmatch(versions[0]) if len(versions) == 1 else None
    if match is None:
        raise ValueError("Expected a cask with one Juggler release version")
    return tuple(int(part) for part in match.groups())


def publish_cask(cask, tap_cask):
    content = cask.read_text()
    release = cask_version(content)
    if tap_cask.exists() and cask_version(tap_cask.read_text()) > release:
        return False
    tap_cask.parent.mkdir(parents=True, exist_ok=True)
    tap_cask.write_text(content)
    return True


def main():
    parser = argparse.ArgumentParser()
    operations = parser.add_subparsers(dest="operation", required=True)
    render = operations.add_parser("render")
    render.add_argument("version")
    render.add_argument("app", type=Path)
    render.add_argument("dmg", type=Path)
    render.add_argument("output", type=Path)
    publish = operations.add_parser("publish")
    publish.add_argument("cask", type=Path)
    publish.add_argument("tap_cask", type=Path)
    args = parser.parse_args()
    if args.operation == "publish":
        print("updated" if publish_cask(args.cask, args.tap_cask) else "skipped-newer")
        return
    contents = render_cask(args.version, args.app, args.dmg)
    args.output.write_text(contents)


if __name__ == "__main__":
    main()

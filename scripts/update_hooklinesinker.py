import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import hooklinesinker as hls


REPOSITORY = "nielsmadan/hooklinesinker"
ROOT = hls.ROOT


def version_tuple(version):
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError(f"Expected a stable version such as 1.0.1, got {version!r}")
    return tuple(map(int, version.split(".")))


def published_release(version=None):
    if version is not None:
        version = version.removeprefix("v")
        version_tuple(version)
    endpoint = f"tags/v{version}" if version else "latest"
    request = Request(
        f"https://api.github.com/repos/{REPOSITORY}/releases/{endpoint}",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "juggler-hls-update"},
    )
    try:
        with urlopen(request, timeout=15) as response:
            release = json.load(response)
    except HTTPError as error:
        if error.code == 404:
            raise ValueError("No published HLS release found; check that its release workflow completed successfully") from error
        raise
    tag = release["tag_name"]
    if not isinstance(tag, str):
        raise ValueError("The published release has an invalid tag")
    version_tuple(tag.removeprefix("v"))
    if not tag.startswith("v") or release["draft"] or release["prerelease"]:
        raise ValueError("Expected a published stable HLS release")
    if version is not None and tag != f"v{version}":
        raise ValueError("The published release does not match the requested version")
    return release


def release_revision(tag):
    ref = f"refs/tags/{tag}"
    output = hls.run("git", "ls-remote", f"https://github.com/{REPOSITORY}.git", ref, ref + "^{}")
    refs = {}
    for line in output.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] in (ref, ref + "^{}"):
            refs[parts[1]] = parts[0]
    revision = refs.get(ref + "^{}", refs.get(ref, ""))
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError(f"Could not resolve the commit for {tag}")
    return revision


def warning(message):
    prefix = "::warning::" if os.environ.get("GITHUB_ACTIONS") == "true" else "WARNING: "
    print(prefix + message, file=sys.stderr)


def check_update(pin):
    try:
        release = published_release()
        version = release["tag_name"][1:]
        if version_tuple(version) > version_tuple(pin["version"]):
            warning(
                f"HLS {version} is published; Juggler pins {pin['version']}. "
                "Run just update-hooklinesinker, then build, verify and commit the update. "
                f"https://github.com/{REPOSITORY}/releases/tag/v{version}"
            )
        else:
            print(f"HLS pinned: {pin['version']}; latest published: {version}.")
    except (OSError, ValueError, KeyError, TypeError) as error:
        warning(f"Could not check for HLS updates: {error}. Continuing with {pin['version']}.")


def write_pins(contents, originals):
    with tempfile.TemporaryDirectory(dir=ROOT / "scripts", prefix=".hls-update-") as temporary:
        temporary = Path(temporary)
        for path, content in contents.items():
            candidate = temporary / path.name
            candidate.write_bytes(content)
            candidate.chmod(path.stat().st_mode & 0o777)
            shutil.copy2(path, temporary / (path.name + ".previous"))
        if any(path.read_bytes() != original for path, original in originals.items()):
            raise ValueError("The HLS pins changed during the update; retry with the current files")
        replaced = []
        try:
            for path in contents:
                os.replace(temporary / path.name, path)
                replaced.append(path)
        except OSError:
            for path in reversed(replaced):
                os.replace(temporary / (path.name + ".previous"), path)
            raise


def update(pin, version=None):
    pin_path = ROOT / "scripts/hooklinesinker.json"
    remote_path = ROOT / "scripts/install-remote.sh"
    originals = {path: path.read_bytes() for path in (pin_path, remote_path)}
    if hls.read_pin(ROOT) != pin:
        raise ValueError("The HLS pins changed; retry with the current files")
    release = published_release(version)
    version = release["tag_name"][1:]
    if version_tuple(version) < version_tuple(pin["version"]):
        raise ValueError(f"Refusing to downgrade HLS from {pin['version']} to {version}")
    assets = {asset["name"] for asset in release["assets"]}
    if not {hls.ARTIFACT, "SHA256SUMS"}.issubset(assets):
        raise ValueError("The published release needs the universal macOS binary and SHA256SUMS")
    candidate = dict(pin, version=version, sourceRevision=release_revision(release["tag_name"]))
    if candidate == pin:
        print(f"HLS {version} is already pinned to its release commit.")
        return
    with tempfile.TemporaryDirectory(prefix="juggler-hls-update-") as temporary:
        dist = Path(temporary)
        hls.download(candidate, dist)
        binary = dist / hls.ARTIFACT
        hls.verify_checksum(binary, dist / "SHA256SUMS")
        binary.chmod(0o755)
        hls.verify_binary(binary, candidate)
    remote, count = re.subn(
        r"HOOKLINESINKER_VERSION:-v[^}]+", f"HOOKLINESINKER_VERSION:-v{version}",
        originals[remote_path].decode(),
    )
    if count != 1:
        raise ValueError("Expected one HLS version default in the remote installer")
    write_pins({
        pin_path: (json.dumps(candidate, indent=2) + "\n").encode(),
        remote_path: remote.encode(),
    }, originals)
    print(f"Updated HLS {pin['version']} -> {version} ({candidate['sourceRevision']}).")
    print("Next: just build, just verify-hooklinesinker, then review and commit both pin files.")


def main():
    parser = argparse.ArgumentParser(description="Update Juggler's HLS pin from a published release.")
    parser.add_argument("version", nargs="?", help="stable version; defaults to the latest published release")
    parser.add_argument("--check", action="store_true", help="warn about newer releases without changing pins")
    args = parser.parse_args()
    if args.check and args.version:
        parser.error("--check always checks the latest published release")
    try:
        pin = hls.read_pin(ROOT)
        if args.check:
            check_update(pin)
        else:
            update(pin, args.version)
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"hooklinesinker: {error}\n")


if __name__ == "__main__":
    main()

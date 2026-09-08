import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT = "hooklinesinker-macos-universal"
IDENTIFIER = "com.nielsmadan.hooklinesinker"
ARCHITECTURES = {"arm64", "x86_64"}


def run(*arguments, environment=None):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=60, env=environment)
    if result.returncode:
        raise ValueError(f"{' '.join(map(str, arguments))}: {result.stdout}{result.stderr}")
    return result.stdout + result.stderr


def read_pin(root=ROOT):
    pin = json.loads((root / "scripts/hooklinesinker.json").read_text())
    if not re.fullmatch(r"\d+\.\d+\.\d+", pin["version"]):
        raise ValueError("Invalid hooklinesinker version pin")
    if pin["protocol"] != 1 or not re.fullmatch(r"[0-9a-f]{40}", pin["sourceRevision"]):
        raise ValueError("Invalid hooklinesinker protocol or source revision pin")
    remote_versions = re.findall(
        r"HOOKLINESINKER_VERSION:-v([^}]+)",
        (root / "scripts/install-remote.sh").read_text(),
    )
    if remote_versions != [pin["version"]]:
        raise ValueError("The remote installer and embedded hooklinesinker version pins differ")
    return pin


def verify_checksum(binary, manifest):
    entries = [line.split() for line in manifest.read_text().splitlines()]
    matches = [parts[0] for parts in entries
               if len(parts) == 2 and parts[1].lstrip("*") == ARTIFACT]
    if len(matches) != 1 or not re.fullmatch(r"[0-9a-fA-F]{64}", matches[0]):
        raise ValueError(f"SHA256SUMS must contain exactly one valid entry for {ARTIFACT}")
    if hashlib.sha256(binary.read_bytes()).hexdigest() != matches[0].lower():
        raise ValueError(f"Checksum mismatch for {ARTIFACT}")


def verify_binary(binary, pin):
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise ValueError(f"Missing executable hooklinesinker: {binary}")
    architectures = set(run("lipo", "-archs", str(binary)).split())
    if architectures != ARCHITECTURES:
        raise ValueError(f"Expected arm64 and x86_64 hooklinesinker; found {sorted(architectures)}")
    version = json.loads(run(str(binary), "version", "--json"))
    if version.get("version") != pin["version"] or version.get("protocol") != pin["protocol"]:
        raise ValueError(f"Hooklinesinker version/protocol does not match the pin: {version}")


def stage(dist, output, pin):
    binary = dist / ARTIFACT
    verify_checksum(binary, dist / "SHA256SUMS")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as temporary:
        candidate = Path(temporary) / "hooklinesinker"
        shutil.copyfile(binary, candidate)
        candidate.chmod(0o755)
        verify_binary(candidate, pin)
        run("codesign", "--force", "--sign", "-", "--identifier", IDENTIFIER,
            "--options", "runtime", str(candidate))
        run("codesign", "--verify", "--strict", str(candidate))
        if not output.is_file() or output.read_bytes() != candidate.read_bytes():
            candidate.replace(output)
    print(f"Staged hooklinesinker {pin['version']} ({', '.join(sorted(ARCHITECTURES))})")


def download(pin, output):
    base = f"https://github.com/nielsmadan/hooklinesinker/releases/download/v{pin['version']}"
    output.mkdir(parents=True, exist_ok=True)
    for name in (ARTIFACT, "SHA256SUMS"):
        run("curl", "--fail", "--silent", "--show-error", "--location", "--proto", "=https",
            "--connect-timeout", "10", "--max-time", "45", "--output", str(output / name),
            f"{base}/{name}")


def signature_metadata(binary, architecture):
    return run("codesign", "--display", "--verbose=4", "--arch", architecture, str(binary))


def verify_signature(binary, distribution, team=None):
    run("codesign", "--verify", "--strict", "--all-architectures", str(binary))
    for architecture in sorted(ARCHITECTURES):
        metadata = signature_metadata(binary, architecture)
        if f"Identifier={IDENTIFIER}\n" not in metadata or "runtime)" not in metadata:
            raise ValueError(f"Hooklinesinker {architecture} signature lacks its identifier or hardened runtime")
        if distribution and ("Authority=Developer ID Application:" not in metadata
                             or "\nTimestamp=" not in metadata
                             or f"TeamIdentifier={team}\n" not in metadata):
            raise ValueError(f"Hooklinesinker {architecture} lacks the app's timestamped Developer ID signature")


def verify_bundle(app, pin, distribution=False):
    binary = app / "Contents/MacOS/hooklinesinker"
    if binary.is_symlink():
        raise ValueError("The embedded hooklinesinker must be a regular file")
    team = None
    if distribution:
        run("codesign", "--verify", "--deep", "--strict", "--all-architectures", str(app))
        app_signature = signature_metadata(app, "arm64")
        match = re.search(r"^TeamIdentifier=(\w+)$", app_signature, re.M)
        if not match or "Authority=Developer ID Application:" not in app_signature:
            raise ValueError("Juggler needs a Developer ID Application signature")
        team = match[1]
    verify_signature(binary, distribution, team)
    verify_binary(binary, pin)
    with tempfile.TemporaryDirectory(prefix="juggler-hls-verify-") as temporary:
        data = Path(temporary) / "data"
        state = Path(temporary) / "state"
        environment = dict(os.environ, XDG_DATA_HOME=str(data), XDG_STATE_HOME=str(state))
        run(str(binary), "install", "--consumer", "juggler-release-check", environment=environment)
        installed = data / "hooklinesinker/bin/hooklinesinker"
        verify_signature(installed, distribution, team)
        verify_binary(installed, pin)
    print(f"Verified embedded and promoted hooklinesinker {pin['version']}")


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    stage_parser = commands.add_parser("stage")
    stage_parser.add_argument("--dist", type=Path, default=os.environ.get("HOOKLINESINKER_DIST"))
    stage_parser.add_argument("--published", action="store_true")
    stage_parser.add_argument("--output", type=Path, default=ROOT / "build/hooklinesinker/hooklinesinker")
    verify_parser = commands.add_parser("verify")
    verify_parser.add_argument("app", type=Path)
    verify_parser.add_argument("--distribution", action="store_true")
    commands.add_parser("source-revision")
    args = parser.parse_args()
    try:
        pin = read_pin()
        if args.command == "source-revision":
            print(pin["sourceRevision"])
        elif args.command == "verify":
            verify_bundle(args.app, pin, args.distribution)
        elif args.dist and not args.published:
            stage(args.dist, args.output, pin)
        else:
            dist = ROOT / "build/hooklinesinker/downloads" / pin["version"]
            if args.published or not all((dist / name).is_file() for name in (ARTIFACT, "SHA256SUMS")):
                with tempfile.TemporaryDirectory(prefix="juggler-hls-download-") as temporary:
                    downloaded = Path(temporary)
                    download(pin, downloaded)
                    verify_checksum(downloaded / ARTIFACT, downloaded / "SHA256SUMS")
                    dist.mkdir(parents=True, exist_ok=True)
                    for name in (ARTIFACT, "SHA256SUMS"):
                        shutil.copyfile(downloaded / name, dist / name)
            stage(dist, args.output, pin)
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"hooklinesinker: {error}\n")


if __name__ == "__main__":
    main()

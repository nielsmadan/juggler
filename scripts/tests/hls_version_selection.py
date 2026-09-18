#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

SINK = "http://127.0.0.1:7483/hook"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(value):
    return hashlib.sha256(value).hexdigest()


def record_digest(value):
    return digest(json.dumps(value, sort_keys=True).encode())


def call(binary, *arguments, environment=None):
    result = subprocess.run(
        [str(binary), *arguments],
        check=False,
        env=environment,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode:
        raise RuntimeError(
            f"HLS {' '.join(arguments)} failed ({result.returncode}): {result.stderr.strip()}"
        )
    return result.stdout


def read(binary, *arguments, environment=None):
    return json.loads(call(binary, *arguments, "--json", environment=environment))


def release_version(version):
    require(
        re.fullmatch(r"\d+\.\d+\.\d+", version) is not None,
        "Use stable major.minor.patch fixture versions",
    )
    return tuple(map(int, version.split(".")))


def fingerprint(binary):
    stat = binary.stat()
    target = os.readlink(binary) if binary.is_symlink() else None
    return {
        "sha256": digest(binary.read_bytes()),
        "inode": stat.st_ino,
        "mtimeNs": stat.st_mtime_ns,
        "symlinkSha256": digest(target.encode()) if target is not None else None,
    }


def consumers(binary, environment=None):
    result = read(binary, "consumers", environment=environment)
    require(result["problems"] == [], "Consumer parsing reported problems")
    records = result["consumers"]
    by_name = {item["name"]: item for item in records}
    require(len(by_name) == len(records), "Duplicate consumer registrations")
    return by_name


def matrix(args):
    binaries = {
        "older": args.older.resolve(),
        "same": args.bundled.resolve(),
        "newer": args.newer.resolve(),
    }
    versions = {name: read(binary, "version") for name, binary in binaries.items()}
    require(
        len({item["protocol"] for item in versions.values()}) == 1,
        "All fixtures must use the bundled protocol",
    )
    ordered = [
        release_version(versions[name]["version"])
        for name in ("older", "same", "newer")
    ]
    require(ordered[0] < ordered[1] < ordered[2], "Expected older < bundled < newer")
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    report = {
        "fixtures": {
            name: {**versions[name], "sha256": digest(binary.read_bytes())}
            for name, binary in binaries.items()
        },
        "cases": [],
        "result": "INCOMPLETE",
    }
    report_path = root / "matrix-results.json"
    try:
        for name, preinstalled in binaries.items():
            case = root / name
            case.mkdir()
            environment = dict(
                os.environ,
                XDG_DATA_HOME=str(case / "data"),
                XDG_STATE_HOME=str(case / "state"),
            )
            active = case / "data/hooklinesinker/bin/hooklinesinker"
            call(
                preinstalled,
                "install",
                "--consumer",
                "existing-tool",
                environment=environment,
            )
            before_version = read(active, "version", environment=environment)
            before = fingerprint(active)
            previous = consumers(active, environment)
            require(
                before_version == versions[name], f"{name}: fixture activation failed"
            )
            require(
                before["sha256"] == report["fixtures"][name]["sha256"],
                f"{name}: initial hash mismatch",
            )
            require(
                set(previous) == {"existing-tool"},
                f"{name}: unexpected initial consumers",
            )
            call(
                binaries["same"],
                "install",
                "--consumer",
                "juggler",
                "--sink",
                SINK,
                environment=environment,
            )
            after_version = read(active, "version", environment=environment)
            after = fingerprint(active)
            current = consumers(active, environment)
            expected = "newer" if name == "newer" else "same"
            require(
                after_version == versions[expected],
                f"{name}: wrong active version/protocol",
            )
            require(
                after["sha256"] == report["fixtures"][expected]["sha256"],
                f"{name}: active hash mismatch",
            )
            require(
                set(current) == {"existing-tool", "juggler"},
                f"{name}: unexpected consumers",
            )
            require(
                current["existing-tool"] == previous["existing-tool"],
                f"{name}: existing consumer changed",
            )
            require(current["juggler"]["sink"] == SINK, f"{name}: wrong Juggler sink")
            require(
                current["juggler"]["protocol"] == versions["same"]["protocol"],
                f"{name}: wrong consumer protocol",
            )
            require(
                current["juggler"]["capabilities"] == ["status"],
                f"{name}: wrong consumer capabilities",
            )
            if name != "older":
                require(before == after, f"{name}: retained binary or symlink changed")
            report["cases"].append(
                {
                    "case": name,
                    "beforeVersion": before_version,
                    "afterVersion": after_version,
                    "before": before,
                    "after": after,
                    "consumers": current,
                    "result": "PASS",
                }
            )
            print(
                f"PASS {name}: {before_version['version']} -> {after_version['version']}"
            )
        report["result"] = "PASS"
    finally:
        report_path.write_text(json.dumps(report, indent=2) + "\n")


def inspect(args):
    binary = args.active.expanduser().absolute()
    records = consumers(binary)
    hooks = read(binary, "hooks", "status", "--agent", "claude")
    settings = Path(hooks["path"])
    report = {
        "version": read(binary, "version"),
        "binary": fingerprint(binary),
        "jugglerRegistered": "juggler" in records,
        "jugglerSinkMatches": records.get("juggler", {}).get("sink") == SINK,
        "consumerDigests": sorted(record_digest(record) for record in records.values()),
        "otherConsumerDigests": sorted(
            record_digest(record)
            for name, record in records.items()
            if name != "juggler"
        ),
        "hooks": {
            "state": hooks["state"],
            "count": len(hooks["entries"]),
            "sha256": record_digest(hooks),
        },
        "settingsSha256": digest(settings.read_bytes()) if settings.is_file() else None,
    }
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(
        description="Check shared HLS selection without installing host hooks."
    )
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser(
        "matrix", help="Run older/equal/newer cases in a new output directory"
    )
    for name in ("bundled", "older", "newer", "output"):
        check.add_argument(f"--{name}", type=Path, required=True)
    check.set_defaults(run=matrix)
    snapshot = commands.add_parser(
        "inspect", help="Read-only, path-free guest helper/configuration snapshot"
    )
    data_home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    snapshot.add_argument(
        "--active", type=Path, default=data_home / "hooklinesinker/bin/hooklinesinker"
    )
    snapshot.set_defaults(run=inspect)
    args = parser.parse_args()
    try:
        args.run(args)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"FAIL: {error}\n")


if __name__ == "__main__":
    main()

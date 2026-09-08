import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

import codex_config_cleanup


def expand_path(value, user_directory):
    if value == "~":
        return user_directory
    if value.startswith("~/"):
        return user_directory / value[2:]
    return Path(value)


def remove_path(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def read_json(path):
    if not path.exists() and not path.is_symlink():
        return None
    with path.open() as file:
        data = json.load(file)
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return data


def write_json(path, data):
    if not data and not path.is_symlink():
        path.unlink()
    else:
        codex_config_cleanup.atomic_write(str(path.resolve()), json.dumps(data, indent=2) + "\n")


def runs_script(command, script, user_directory):
    if not isinstance(command, str):
        return False
    try:
        words = shlex.split(command)
    except ValueError:
        return False
    return bool(words) and expand_path(words[0], user_directory) == script


def clean_hook_groups(data, script, user_directory):
    hooks = data.get("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("'hooks' must contain a JSON object")
    cleaned = {}
    for event, groups in hooks.items():
        if not isinstance(groups, list):
            raise ValueError(f"hooks.{event} must contain an array")
        retained_groups = []
        for group in groups:
            if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
                raise ValueError(f"hooks.{event} contains an invalid hook group")
            handlers = group["hooks"]
            retained = [handler for handler in handlers if not (
                isinstance(handler, dict)
                and handler.get("type", "command") == "command"
                and runs_script(handler.get("command"), script, user_directory)
            )]
            if retained == handlers:
                retained_groups.append(group)
            elif retained:
                retained_groups.append({**group, "hooks": retained})
        if retained_groups:
            cleaned[event] = retained_groups
    if cleaned == hooks:
        return data
    result = dict(data)
    if cleaned:
        result["hooks"] = cleaned
    else:
        result.pop("hooks", None)
    return result


def clean_agent(user_directory, agent):
    directory = user_directory / f".{agent}"
    path = directory / ("settings.json" if agent == "claude" else "hooks.json")
    script = directory / "hooks/juggler/notify.sh"
    data = read_json(path)
    updated = clean_hook_groups(data, script, user_directory) if data is not None else None
    if agent == "codex":
        config = directory / "config.toml"
        codex_config_cleanup.cleanup(str(config), str(path), str(script))
    if updated != data:
        write_json(path, updated)
    if agent == "codex":
        remove_path(directory / "config.toml.juggler-backup")
    remove_path(directory / "hooks/juggler")
    remove_path(Path(str(path) + ".juggler-backup"))


def clean_antigravity(user_directory):
    path = user_directory / ".gemini/config/hooks.json"
    data = read_json(path)
    if data is not None and "juggler" in data:
        del data["juggler"]
        write_json(path, data)
    remove_path(user_directory / ".gemini/hooks/juggler")
    remove_path(Path(str(path) + ".juggler-backup"))


def clean_kitty(directory, user_directory):
    watcher = directory / "juggler_watcher.py"
    config = directory / "kitty.conf"
    if config.exists() or config.is_symlink():
        contents = config.read_text()
        retained = []
        for line in contents.splitlines(keepends=True):
            words = line.split(None, 1)
            if len(words) == 2 and words[0] == "watcher":
                target = expand_path(words[1].strip(), user_directory)
                if not target.is_absolute():
                    target = directory / target
                if target == watcher:
                    continue
            retained.append(line)
        updated = "".join(retained)
        if updated != contents:
            codex_config_cleanup.atomic_write(str(config.resolve()), updated)
    remove_path(watcher)


def hooklinesinker_executable(user_directory, environment):
    data = expand_path(environment.get("XDG_DATA_HOME") or "~/.local/share", user_directory)
    candidates = [
        data / "hooklinesinker/bin/hooklinesinker",
        Path(__file__).resolve().parent.parent / "MacOS/hooklinesinker",
    ]
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.resolve()
    return None


def run_hooklinesinker(executable, arguments, environment):
    result = subprocess.run([str(executable), *arguments], env=environment,
                            text=True, capture_output=True, timeout=30)
    if result.returncode:
        raise ValueError(result.stderr.strip() or result.stdout.strip()
                         or f"hooklinesinker exited with status {result.returncode}")
    return result.stdout


def codex_hook_status(executable, environment):
    status = json.loads(run_hooklinesinker(
        executable, ["hooks", "status", "--agent", "codex", "--json"], environment,
    ))
    if not isinstance(status, dict) or type(status.get("protocol")) is not int or status["protocol"] != 1:
        raise ValueError("Unsupported hooklinesinker status protocol")
    if (status.get("agent") != "codex"
            or status.get("state") not in ("missing", "installed", "drifted", "unsupported")
            or not isinstance(status.get("path"), str) or not status["path"]
            or not isinstance(status.get("entries"), list)):
        raise ValueError("Unreadable Codex hook status")
    for entry in status["entries"]:
        if (not isinstance(entry, dict) or not isinstance(entry.get("event"), str) or not entry["event"]
                or type(entry.get("groupIndex")) is not int or entry["groupIndex"] < 0
                or not isinstance(entry.get("command"), str) or not entry["command"]):
            raise ValueError("Unreadable Codex hook entry")
    return status


def clean_shared_hooks(user_directory, environment):
    executable = hooklinesinker_executable(user_directory, environment)
    if executable is None:
        return
    child_environment = dict(environment, HOME=str(user_directory))
    registration = codex_hook_status(executable, child_environment)
    output = run_hooklinesinker(executable, ["uninstall", "--consumer", "juggler"], child_environment)
    if output.strip():
        print(f"  {output.strip()}")
    if not registration["entries"]:
        return
    remaining = codex_hook_status(executable, child_environment)
    if remaining["path"] != registration["path"]:
        raise ValueError("Codex hook path changed during uninstall; trust entries were left in place")
    if remaining["state"] != "missing" or remaining["entries"]:
        print("  Kept Codex trust for the remaining shared hooks")
        return
    hashes = {
        f'{registration["path"]}:{codex_config_cleanup.snake_case_event(entry["event"])}:{entry["groupIndex"]}:0':
            codex_config_cleanup.command_hash(entry["event"], entry["command"])
        for entry in registration["entries"]
    }
    if codex_config_cleanup.cleanup_trusted_hashes(str(user_directory / ".codex/config.toml"), hashes):
        print("  Removed Juggler trust entries from Codex config.toml")


def cleanup_integrations(user_directory, environment):
    config_home = expand_path(environment.get("XDG_CONFIG_HOME") or "~/.config", user_directory)
    kitty = expand_path(environment.get("KITTY_CONFIG_DIRECTORY") or str(config_home / "kitty"), user_directory)
    opencode = expand_path(environment.get("OPENCODE_CONFIG_DIR") or str(config_home / "opencode"), user_directory)
    pi = expand_path(environment.get("PI_CODING_AGENT_DIR") or "~/.pi/agent", user_directory)
    actions = [
        ("Shared hooks", lambda: clean_shared_hooks(user_directory, environment)),
        ("Claude Code", lambda: clean_agent(user_directory, "claude")),
        ("Codex", lambda: clean_agent(user_directory, "codex")),
        ("Antigravity", lambda: clean_antigravity(user_directory)),
        ("Kitty", lambda: clean_kitty(kitty, user_directory)),
        ("OpenCode", lambda: remove_path(opencode / "plugins/juggler-opencode.ts")),
        ("Pi", lambda: remove_path(pi / "extensions/juggler-pi.ts")),
    ]
    errors = []
    for name, action in actions:
        try:
            action()
            print(f"  Removed {name} integration")
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            errors.append(f"{name}: {error}")
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--home-directory", type=Path, default=Path.home())
    parser.add_argument("--skip-permissions", action="store_true")
    args = parser.parse_args()
    print("Removing Juggler integrations...")
    errors = cleanup_integrations(args.home_directory, os.environ)
    if not args.skip_permissions:
        result = subprocess.run(
            ["tccutil", "reset", "AppleEvents", "com.nielsmadan.Juggler"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            print("  Reset Automation permission")
    if errors:
        for error in errors:
            print(f"  Cleanup failed: {error}", file=sys.stderr)
        raise SystemExit(1)
    print("Done.")


if __name__ == "__main__":
    main()

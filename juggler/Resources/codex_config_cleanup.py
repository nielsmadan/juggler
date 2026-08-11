import hashlib
import json
import os
import re
import stat
import sys
import tempfile


EVENTS = {
    "session_start": ("SessionStart", 5),
    "user_prompt_submit": ("UserPromptSubmit", 5),
    "pre_tool_use": ("PreToolUse", 5),
    "post_tool_use": ("PostToolUse", 5),
    "pre_compact": ("PreCompact", 5),
    "post_compact": ("PostCompact", 5),
    "permission_request": ("PermissionRequest", 5),
    "stop": ("Stop", 5),
    "session_end": ("SessionEnd", 3),
}

HOOK_STATE_HEADER = re.compile(r'^\[hooks\.state\."(.*)"\]$')
TRUSTED_HASH = re.compile(r'^trusted_hash\s*=\s*"([^"]+)"')


def snake_case_event(event):
    for snake, (name, _) in EVENTS.items():
        if name == event:
            return snake
    return event.lower()


def expected_hash(event, notify_script_path):
    snake = snake_case_event(event)
    timeout = EVENTS.get(snake, (event, 5))[1]
    payload = {
        "event_name": snake,
        "hooks": [
            {
                "async": False,
                "command": f"{notify_script_path} {event}",
                "timeout": timeout,
                "type": "command",
            }
        ],
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(encoded.encode()).hexdigest()


def current_juggler_keys(hooks_json_path, notify_script_path):
    try:
        with open(hooks_json_path) as file:
            root = json.load(file)
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return set()

    keys = set()
    hooks = root.get("hooks", {}) if isinstance(root, dict) else {}
    if not isinstance(hooks, dict):
        return keys

    for event, groups in hooks.items():
        if not isinstance(groups, list):
            continue
        for group_index, group in enumerate(groups):
            handlers = group.get("hooks", []) if isinstance(group, dict) else []
            if not isinstance(handlers, list):
                continue
            for handler_index, handler in enumerate(handlers):
                command = handler.get("command") if isinstance(handler, dict) else None
                if isinstance(command, str) and notify_script_path in command:
                    keys.add(f"{hooks_json_path}:{snake_case_event(event)}:{group_index}:{handler_index}")
    return keys


def section_key(section):
    if not section:
        return None
    match = HOOK_STATE_HEADER.match(section[0].strip())
    return match.group(1) if match else None


def section_hash(section):
    for line in section[1:]:
        match = TRUSTED_HASH.match(line.strip())
        if match:
            return match.group(1)
    return None


def is_juggler_section(section, hooks_json_path, notify_script_path, current_keys):
    key = section_key(section)
    if key is None:
        return False
    if key in current_keys:
        return True

    try:
        path, event, _, _ = key.rsplit(":", 3)
    except ValueError:
        return False
    if path != hooks_json_path or event not in EVENTS:
        return False

    event_name, _ = EVENTS[event]
    return section_hash(section) == expected_hash(event_name, notify_script_path)


def split_sections(contents):
    sections = [[]]
    for line in contents.splitlines(keepends=True):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            sections.append([])
        sections[-1].append(line)
    return sections


def atomic_write(path, contents):
    directory = os.path.dirname(path)
    descriptor, temporary_path = tempfile.mkstemp(prefix=".config.toml.juggler-", dir=directory)
    try:
        with os.fdopen(descriptor, "w") as file:
            file.write(contents)
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary_path, stat.S_IMODE(os.stat(path).st_mode))
        os.replace(temporary_path, path)
    except BaseException:
        try:
            os.unlink(temporary_path)
        except FileNotFoundError:
            pass
        raise


def main():
    config_path, hooks_json_path, notify_script_path = sys.argv[1:]
    try:
        with open(config_path) as file:
            contents = file.read()
    except FileNotFoundError:
        return

    current_keys = current_juggler_keys(hooks_json_path, notify_script_path)
    sections = split_sections(contents)
    retained = [
        section
        for section in sections
        if not is_juggler_section(section, hooks_json_path, notify_script_path, current_keys)
    ]
    updated = "".join("".join(section) for section in retained)
    if updated != contents:
        atomic_write(os.path.realpath(config_path), updated)
        print("  Removed Juggler trust entries from Codex config.toml")


if __name__ == "__main__":
    main()

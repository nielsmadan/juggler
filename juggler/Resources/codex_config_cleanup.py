import hashlib
import json
import os
import re
import shlex
import stat
import sys
import tempfile
from io import StringIO


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

HOOK_STATE_HEADER = re.compile(r'^\[hooks\.state\."((?:[^"\\]|\\.)*)"\]\s*(?:#.*)?$')
TRUSTED_HASH = re.compile(r'^trusted_hash\s*=\s*"([^"]+)"')


def snake_case_event(event):
    for snake, (name, _) in EVENTS.items():
        if name == event:
            return snake
    return event.lower()


def expected_hash(event, notify_script_path):
    return command_hash(event, f"{notify_script_path} {event}")


def command_hash(event, command):
    snake = snake_case_event(event)
    timeout = EVENTS.get(snake, (event, 5))[1]
    payload = {
        "event_name": snake,
        "hooks": [
            {
                "async": False,
                "command": command,
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
                if not isinstance(command, str) or handler.get("type", "command") != "command":
                    continue
                try:
                    words = shlex.split(command)
                except ValueError:
                    continue
                if words and words[0] in (notify_script_path, "~/.codex/hooks/juggler/notify.sh"):
                    keys.add(f"{hooks_json_path}:{snake_case_event(event)}:{group_index}:{handler_index}")
    return keys


def section_key(section):
    if not section:
        return None
    match = HOOK_STATE_HEADER.match(section[0].strip())
    return match.group(1) if match else None


def section_hash(section):
    for _, code in toml_lines("".join(section)):
        match = TRUSTED_HASH.match(code)
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


def toml_lines(contents):
    delimiter = None
    brackets = []
    for line in StringIO(contents):
        starts_statement = delimiter is None and not brackets
        position = 0
        while position < len(line):
            character = line[position]
            if delimiter:
                if delimiter[0] == '"' and character == "\\":
                    position += 2
                    continue
                if line.startswith(delimiter, position):
                    end = position + len(delimiter)
                    if len(delimiter) == 3:
                        while end < len(line) and line[end] == delimiter[0]:
                            end += 1
                        if end - position > 5:
                            raise ValueError("Invalid TOML string delimiter")
                    delimiter = None
                    position = end
                    continue
            elif character == "#":
                break
            elif character in ('"', "'"):
                delimiter = character * (3 if line.startswith(character * 3, position) else 1)
                position += len(delimiter)
                continue
            elif character in "[{":
                brackets.append(character)
            elif character in "]}":
                if not brackets or brackets.pop() != {"]": "[", "}": "{"}[character]:
                    raise ValueError("Unbalanced TOML brackets")
            position += 1
        if delimiter and len(delimiter) == 1:
            raise ValueError("Unterminated TOML string")
        code = line[:position].strip() if starts_statement else ""
        if code.startswith("[") and (delimiter or brackets or not code.endswith("]")):
            raise ValueError("Invalid TOML table header")
        yield line, code
    if delimiter or brackets:
        raise ValueError("Unterminated TOML value")


def split_sections(contents):
    sections = [[]]
    for line, code in toml_lines(contents):
        if code.startswith("["):
            sections.append([])
        sections[-1].append(line)
    return sections


def atomic_write(path, contents):
    directory = os.path.dirname(path)
    descriptor, temporary_path = tempfile.mkstemp(prefix=".config.toml.juggler-", dir=directory)
    try:
        with os.fdopen(descriptor, "w", newline="") as file:
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


def cleanup(config_path, hooks_json_path, notify_script_path):
    try:
        with open(config_path, newline="") as file:
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


def cleanup_trusted_hashes(config_path, trusted_hashes):
    if not isinstance(trusted_hashes, dict) or not all(
        isinstance(key, str) and isinstance(value, str) for key, value in trusted_hashes.items()
    ):
        raise ValueError("Expected a map of Codex trust keys to hashes")
    try:
        with open(config_path, newline="") as file:
            contents = file.read()
    except FileNotFoundError:
        return False
    sections = split_sections(contents)
    retained = [section for section in sections
                if section_key(section) not in trusted_hashes
                or section_hash(section) != trusted_hashes[section_key(section)]]
    updated = "".join("".join(section) for section in retained)
    if updated == contents:
        return False
    atomic_write(os.path.realpath(config_path), updated)
    return True


if __name__ == "__main__":
    cleanup(*sys.argv[1:])

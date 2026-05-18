#!/bin/bash
# Installs Juggler hooks for Codex CLI.
# Mirrors CodexHooksInstaller.swift: copies codex-notify.sh, merges hooks.json,
# sets [features] hooks=true in config.toml, and writes [hooks.state."..."]
# trust hashes so Codex runs the hooks without manual review.

set -e

CODEX_DIR="$HOME/.codex"
JUGGLER_HOOKS_DIR="$CODEX_DIR/hooks/juggler"
NOTIFY_SCRIPT="$JUGGLER_HOOKS_DIR/notify.sh"
HOOKS_JSON="$CODEX_DIR/hooks.json"
CONFIG_TOML="$CODEX_DIR/config.toml"
HOOK_TIMEOUT=5

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_NOTIFY="$SCRIPT_DIR/codex-notify.sh"

if [ ! -f "$SOURCE_NOTIFY" ]; then
    echo "Error: codex-notify.sh not found next to install.sh ($SOURCE_NOTIFY)" >&2
    exit 1
fi

echo "Installing Juggler hooks for Codex..."

mkdir -p "$JUGGLER_HOOKS_DIR"
cp "$SOURCE_NOTIFY" "$NOTIFY_SCRIPT"
chmod +x "$NOTIFY_SCRIPT"

export JUGGLER_HOOKS_JSON="$HOOKS_JSON"
export JUGGLER_CONFIG_TOML="$CONFIG_TOML"
export JUGGLER_NOTIFY_SCRIPT="$NOTIFY_SCRIPT"
export JUGGLER_HOOK_TIMEOUT="$HOOK_TIMEOUT"

python3 << 'PYTHON'
import hashlib
import json
import os
import shutil

EVENTS = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
    "PreCompact", "PostCompact", "PermissionRequest", "Stop"
]
EVENT_SNAKE = {
    "SessionStart": "session_start",
    "UserPromptSubmit": "user_prompt_submit",
    "PreToolUse": "pre_tool_use",
    "PostToolUse": "post_tool_use",
    "PreCompact": "pre_compact",
    "PostCompact": "post_compact",
    "PermissionRequest": "permission_request",
    "Stop": "stop",
}

hooks_json_path = os.environ["JUGGLER_HOOKS_JSON"]
config_toml_path = os.environ["JUGGLER_CONFIG_TOML"]
notify = os.environ["JUGGLER_NOTIFY_SCRIPT"]
timeout = int(os.environ["JUGGLER_HOOK_TIMEOUT"])


def hook_command(event):
    return f"{notify} {event}"


def is_juggler_group(group):
    handlers = group.get("hooks") if isinstance(group, dict) else None
    if not isinstance(handlers, list):
        return False
    return any(notify in (h.get("command", "") if isinstance(h, dict) else "")
               for h in handlers)


# Merge hooks.json
existed_hooks = os.path.exists(hooks_json_path)
root = {}
if existed_hooks:
    with open(hooks_json_path) as f:
        try:
            root = json.load(f)
        except json.JSONDecodeError as e:
            raise SystemExit(f"hooks.json is unparseable; fix or remove {hooks_json_path}: {e}")
    if not isinstance(root, dict):
        raise SystemExit(f"hooks.json must be a JSON object at top level: {hooks_json_path}")

hooks = root.get("hooks") if isinstance(root.get("hooks"), dict) else {}
group_indices = {}  # event -> index of Juggler group after merge
for event in EVENTS:
    entries = hooks.get(event) if isinstance(hooks.get(event), list) else []
    entries = [g for g in entries if not is_juggler_group(g)]
    juggler_entry = {
        "hooks": [{
            "type": "command",
            "command": hook_command(event),
            "timeout": timeout,
        }]
    }
    entries.append(juggler_entry)
    group_indices[event] = len(entries) - 1
    hooks[event] = entries
root["hooks"] = hooks

if existed_hooks:
    backup = hooks_json_path + ".juggler-backup"
    if not os.path.exists(backup):
        shutil.copy2(hooks_json_path, backup)

with open(hooks_json_path, "w") as f:
    json.dump(root, f, indent=2, sort_keys=True)
    f.write("\n")


# Compute trusted_hash for each Juggler hook
def trusted_hash(event):
    handler = {
        "async": False,
        "command": hook_command(event),
        "timeout": timeout,
        "type": "command",
    }
    identity = {
        "event_name": EVENT_SNAKE[event],
        "hooks": [handler],
    }
    # ensure_ascii=False keeps non-ASCII bytes as UTF-8, matching Swift's
    # JSONSerialization output — critical for byte-identical trust hashes when
    # the install path contains non-ASCII characters.
    payload = json.dumps(identity, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(payload.encode("utf-8")).hexdigest()


def trust_key(event):
    return f"{hooks_json_path}:{EVENT_SNAKE[event]}:{group_indices[event]}:0"


# Edit config.toml: ensure [features] hooks = true, then upsert
# [hooks.state."..."] blocks for each Juggler hook.
existed_toml = os.path.exists(config_toml_path)
original = ""
if existed_toml:
    with open(config_toml_path) as f:
        original = f.read()


def edit_features(text):
    """Ensure [features] hooks = true. Idempotent. Migrates deprecated codex_hooks."""
    lines = text.split("\n") if text else []
    section = ""
    hooks_idx = None
    legacy_idx = None
    features_end = None

    for i, raw in enumerate(lines):
        line = raw.strip()
        if line.startswith("[") and line.endswith("]"):
            if section == "features":
                features_end = i
            section = line[1:-1]
            continue
        if section == "features":
            # Exact key match — a prefix check would clobber unrelated keys
            # like `hooks_timeout = 30`.
            key = line.split("=", 1)[0].strip() if "=" in line else ""
            if key == "hooks":
                hooks_idx = i
            elif key == "codex_hooks":
                legacy_idx = i
    if section == "features" and features_end is None:
        features_end = len(lines)

    if hooks_idx is not None:
        lines[hooks_idx] = "hooks = true"
        if legacy_idx is not None:
            del lines[legacy_idx]
        return "\n".join(lines) + ("\n" if text.endswith("\n") else "")
    if legacy_idx is not None:
        lines[legacy_idx] = "hooks = true"
        return "\n".join(lines) + ("\n" if text.endswith("\n") else "")
    if features_end is not None:
        lines.insert(features_end, "hooks = true")
        return "\n".join(lines) + ("\n" if text.endswith("\n") else "")
    # No [features] section at all
    suffix = "" if text.endswith("\n") or not text else "\n"
    return text + suffix + "\n[features]\nhooks = true\n"


def upsert_trust_blocks(text):
    """Remove existing Juggler trust blocks (exact-key match), append fresh ones."""
    current_keys = {trust_key(e) for e in EVENTS}
    out = []
    skipping = False
    for raw in text.split("\n") if text else []:
        stripped = raw.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if stripped.startswith('[hooks.state."') and stripped.endswith('"]'):
                key = stripped[len('[hooks.state."'):-len('"]')]
                skipping = key in current_keys
            else:
                skipping = False
        if not skipping:
            out.append(raw)
    while out and out[-1].strip() == "":
        out.pop()
    blocks = []
    for event in EVENTS:
        key = trust_key(event)
        h = trusted_hash(event)
        blocks.append(f'[hooks.state."{key}"]\ntrusted_hash = "{h}"\n')
    preserved = "\n".join(out)
    if preserved:
        return preserved + "\n\n" + "\n".join(blocks)
    return "\n".join(blocks)


updated = edit_features(original if existed_toml else "")
updated = upsert_trust_blocks(updated)

if updated != original:
    if existed_toml:
        backup = config_toml_path + ".juggler-backup"
        if not os.path.exists(backup):
            shutil.copy2(config_toml_path, backup)
    with open(config_toml_path, "w") as f:
        f.write(updated)
        if not updated.endswith("\n"):
            f.write("\n")

print("Codex hooks installed for 8 events: " + ", ".join(EVENTS))
PYTHON

echo "Juggler Codex hooks installed successfully!"
echo "  Notify script: $NOTIFY_SCRIPT"
echo "  Registered in: $HOOKS_JSON"
echo "  Trusted in:    $CONFIG_TOML"

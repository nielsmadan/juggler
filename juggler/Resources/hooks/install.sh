#!/bin/bash
# Installs Juggler hooks for Claude Code

set -e

JUGGLER_HOOKS_DIR="$HOME/.claude/hooks/juggler"
SETTINGS_FILE="$HOME/.claude/settings.json"
SCRIPT_DIR="$(dirname "$0")"

echo "Installing Juggler hooks..."

python3 - "$SETTINGS_FILE" "$SCRIPT_DIR/notify.sh" "$JUGGLER_HOOKS_DIR/notify.sh" << 'PYTHON'
import json
import os
import shutil
import stat
import sys
import tempfile

settings_path, notify_source, notify_destination = sys.argv[1:]
settings_existed = os.path.exists(settings_path)
settings_write_path = os.path.realpath(settings_path)

if settings_existed:
    try:
        with open(settings_path, "r") as f:
            settings = json.load(f)
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"Claude Code settings.json is unreadable or invalid; no changes made: {error}")
    if not isinstance(settings, dict):
        raise SystemExit("Claude Code settings.json must contain a JSON object; no changes made")
else:
    settings = {}

hooks = settings.get("hooks")
if hooks is None:
    hooks = {}
    settings["hooks"] = hooks
elif not isinstance(hooks, dict):
    raise SystemExit("Claude Code settings.json 'hooks' must contain a JSON object; no changes made")

notify_cmd = "~/.claude/hooks/juggler/notify.sh"

# Events with matchers use "*" to match all tools
hook_configs = {
    "SessionStart": [{
        "hooks": [{"type": "command", "command": f"{notify_cmd} SessionStart", "timeout": 5}]
    }],
    "SessionEnd": [{
        "hooks": [{"type": "command", "command": f"{notify_cmd} SessionEnd", "timeout": 5}]
    }],

    "UserPromptSubmit": [{
        "hooks": [{"type": "command", "command": f"{notify_cmd} UserPromptSubmit", "timeout": 5}]
    }],

    "PreToolUse": [{
        "matcher": "*",
        "hooks": [{"type": "command", "command": f"{notify_cmd} PreToolUse", "timeout": 5}]
    }],
    "PostToolUse": [{
        "matcher": "*",
        "hooks": [{"type": "command", "command": f"{notify_cmd} PostToolUse", "timeout": 5}]
    }],
    "PostToolUseFailure": [{
        "matcher": "*",
        "hooks": [{"type": "command", "command": f"{notify_cmd} PostToolUseFailure", "timeout": 5}]
    }],

    "PermissionRequest": [{
        "matcher": "*",
        "hooks": [{"type": "command", "command": f"{notify_cmd} PermissionRequest", "timeout": 5}]
    }],

    # Note: SubagentStop is intentionally NOT hooked - it fires asynchronously after Stop
    # and would overwrite the idle state. See docs/tech/hooks.md for details.
    "SubagentStart": [{
        "hooks": [{"type": "command", "command": f"{notify_cmd} SubagentStart", "timeout": 5}]
    }],

    "Stop": [{
        "hooks": [{"type": "command", "command": f"{notify_cmd} Stop", "timeout": 5}]
    }],
    "StopFailure": [{
        "hooks": [{"type": "command", "command": f"{notify_cmd} StopFailure", "timeout": 5}]
    }],

    "PreCompact": [{
        "matcher": "*",
        "hooks": [{"type": "command", "command": f"{notify_cmd} PreCompact", "timeout": 5}]
    }]
}

# Remove old Notification hooks (deprecated - we use Stop and PermissionRequest now)
if "Notification" in hooks:
    hooks["Notification"] = [h for h in hooks["Notification"] if "juggler/notify.sh" not in str(h)]
    if not hooks["Notification"]:
        del hooks["Notification"]

# Remove SubagentStop hooks (deprecated - fires after Stop and would overwrite idle state)
if "SubagentStop" in hooks:
    hooks["SubagentStop"] = [h for h in hooks["SubagentStop"] if "juggler/notify.sh" not in str(h)]
    if not hooks["SubagentStop"]:
        del hooks["SubagentStop"]

for event, configs in hook_configs.items():
    entries = hooks.get(event, [])
    if not isinstance(entries, list):
        raise SystemExit(f"Claude Code settings.json hooks.{event} must contain a JSON array; no changes made")

    hooks[event] = [entry for entry in entries if "juggler/notify.sh" not in str(entry)]

    hooks[event].extend(configs)

settings_directory = os.path.dirname(settings_write_path)
os.makedirs(settings_directory, exist_ok=True)

if settings_existed:
    backup_path = settings_path + ".juggler-backup"
    if not os.path.exists(backup_path):
        shutil.copy2(settings_path, backup_path)

os.makedirs(os.path.dirname(notify_destination), exist_ok=True)
shutil.copy2(notify_source, notify_destination)
os.chmod(notify_destination, 0o755)

descriptor, temporary_path = tempfile.mkstemp(prefix=".settings.json.juggler-", dir=settings_directory)
try:
    with os.fdopen(descriptor, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    if settings_existed:
        mode = stat.S_IMODE(os.stat(settings_path).st_mode)
        os.chmod(temporary_path, mode)
    os.replace(temporary_path, settings_write_path)
except BaseException:
    try:
        os.unlink(temporary_path)
    except FileNotFoundError:
        pass
    raise

print("Hooks added to settings.json")
PYTHON

echo "Juggler hooks installed successfully!"
echo "Hooks directory: $JUGGLER_HOOKS_DIR"
echo ""
echo "Installed hooks for 11 Claude Code events:"
echo "  - SessionStart, SessionEnd"
echo "  - UserPromptSubmit"
echo "  - PreToolUse, PostToolUse, PostToolUseFailure"
echo "  - PermissionRequest"
echo "  - SubagentStart"
echo "  - Stop, StopFailure"
echo "  - PreCompact"

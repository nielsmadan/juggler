#!/bin/bash
# Installs Juggler hooks for Claude Code

set -e

HOOKS_DIR="$HOME/.claude/hooks"
JUGGLER_HOOKS_DIR="$HOOKS_DIR/juggler"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "Installing Juggler hooks..."

# Create directories
mkdir -p "$JUGGLER_HOOKS_DIR"

# Copy hook script
SCRIPT_DIR="$(dirname "$0")"
cp "$SCRIPT_DIR/notify.sh" "$JUGGLER_HOOKS_DIR/"
chmod +x "$JUGGLER_HOOKS_DIR/notify.sh"

# Check if settings.json exists
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "{}" > "$SETTINGS_FILE"
fi

# Add hooks to settings.json using Python (available on macOS)
python3 << 'PYTHON'
import json
import os

settings_path = os.path.expanduser("~/.claude/settings.json")

try:
    with open(settings_path, "r") as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

if "hooks" not in settings:
    settings["hooks"] = {}

hooks = settings["hooks"]

# Define Juggler hook command
notify_cmd = "~/.claude/hooks/juggler/notify.sh"

# All Claude Code hook events we want to capture
# Events with matchers use "*" to match all tools
hook_configs = {
    # Session lifecycle
    "SessionStart": [{
        "hooks": [{"type": "command", "command": f"{notify_cmd} SessionStart", "timeout": 5}]
    }],
    "SessionEnd": [{
        "hooks": [{"type": "command", "command": f"{notify_cmd} SessionEnd", "timeout": 5}]
    }],

    # User interaction
    "UserPromptSubmit": [{
        "hooks": [{"type": "command", "command": f"{notify_cmd} UserPromptSubmit", "timeout": 5}]
    }],

    # Tool usage
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

    # Permission handling
    "PermissionRequest": [{
        "matcher": "*",
        "hooks": [{"type": "command", "command": f"{notify_cmd} PermissionRequest", "timeout": 5}]
    }],

    # Subagents
    # Note: SubagentStop is intentionally NOT hooked - it fires asynchronously after Stop
    # and would overwrite the idle state. See docs/tech/hooks.md for details.
    "SubagentStart": [{
        "hooks": [{"type": "command", "command": f"{notify_cmd} SubagentStart", "timeout": 5}]
    }],

    # Response completion
    "Stop": [{
        "hooks": [{"type": "command", "command": f"{notify_cmd} Stop", "timeout": 5}]
    }],

    # Context compaction
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
    if event not in hooks:
        hooks[event] = []

    # Remove any existing Juggler hooks for this event
    hooks[event] = [h for h in hooks[event] if "juggler/notify.sh" not in str(h)]

    # Add current Juggler hooks
    hooks[event].extend(configs)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("Hooks added to settings.json")
PYTHON

echo "Juggler hooks installed successfully!"
echo "Hooks directory: $JUGGLER_HOOKS_DIR"
echo ""
echo "Installed hooks for 10 Claude Code events:"
echo "  - SessionStart, SessionEnd"
echo "  - UserPromptSubmit"
echo "  - PreToolUse, PostToolUse, PostToolUseFailure"
echo "  - PermissionRequest"
echo "  - SubagentStart"
echo "  - Stop"
echo "  - PreCompact"

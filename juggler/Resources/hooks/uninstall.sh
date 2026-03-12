#!/bin/bash
# Removes Juggler hooks and integrations

JUGGLER_HOOKS_DIR="$HOME/.claude/hooks/juggler"
SETTINGS_FILE="$HOME/.claude/settings.json"
KITTY_WATCHER="$HOME/.config/kitty/juggler_watcher.py"
OPENCODE_PLUGIN="$HOME/.config/opencode/plugins/juggler-opencode.ts"

echo "Removing Juggler integrations..."

# Remove hooks directory
if [ -d "$JUGGLER_HOOKS_DIR" ]; then
    rm -rf "$JUGGLER_HOOKS_DIR"
    echo "  Removed Claude Code hooks"
fi

# Clean hook entries from settings.json
if [ -f "$SETTINGS_FILE" ]; then
    python3 << 'PYTHON'
import json
import os

settings_path = os.path.expanduser("~/.claude/settings.json")

try:
    with open(settings_path, "r") as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    exit(0)

hooks = settings.get("hooks", {})
modified = False

for event in list(hooks):
    filtered = [h for h in hooks[event] if "juggler/notify.sh" not in str(h)]
    if len(filtered) != len(hooks[event]):
        modified = True
        if filtered:
            hooks[event] = filtered
        else:
            del hooks[event]

if modified:
    tmp_path = settings_path + ".tmp"
    with open(tmp_path, "w") as f:
        json.dump(settings, f, indent=2)
    os.rename(tmp_path, settings_path)
    print("  Cleaned Claude Code settings.json")
PYTHON
fi

# Remove Kitty watcher
if [ -f "$KITTY_WATCHER" ]; then
    rm -f "$KITTY_WATCHER"
    echo "  Removed Kitty watcher"
fi

# Remove OpenCode plugin
if [ -f "$OPENCODE_PLUGIN" ]; then
    rm -f "$OPENCODE_PLUGIN"
    echo "  Removed OpenCode plugin"
fi

# Reset Automation permission
tccutil reset AppleEvents com.nielsmadan.Juggler 2>/dev/null && echo "  Reset Automation permission"

echo "Done."

#!/bin/bash
# Installs Juggler integration for WezTerm
# Idempotent - safe to run multiple times

set -e

# Resolve WezTerm config directory.
# WezTerm searches: $WEZTERM_CONFIG_FILE → ~/.wezterm.lua → $XDG_CONFIG_HOME/wezterm/wezterm.lua → ~/.config/wezterm/wezterm.lua
if [ -n "$WEZTERM_CONFIG_FILE" ]; then
    WEZTERM_CONFIG_LUA="$WEZTERM_CONFIG_FILE"
    WEZTERM_CONFIG_DIR="$(dirname "$WEZTERM_CONFIG_FILE")"
elif [ -f "$HOME/.wezterm.lua" ]; then
    WEZTERM_CONFIG_LUA="$HOME/.wezterm.lua"
    WEZTERM_CONFIG_DIR="$HOME"
elif [ -n "$XDG_CONFIG_HOME" ] && [ -d "$XDG_CONFIG_HOME/wezterm" ]; then
    WEZTERM_CONFIG_DIR="$XDG_CONFIG_HOME/wezterm"
    WEZTERM_CONFIG_LUA="$WEZTERM_CONFIG_DIR/wezterm.lua"
else
    WEZTERM_CONFIG_DIR="$HOME/.config/wezterm"
    WEZTERM_CONFIG_LUA="$WEZTERM_CONFIG_DIR/wezterm.lua"
fi

LUA_DEST="$WEZTERM_CONFIG_DIR/juggler_wezterm.lua"
REQUIRE_LINE="require 'juggler_wezterm'"

SCRIPT_DIR="$(dirname "$0")"
LUA_SOURCE="$SCRIPT_DIR/juggler_wezterm.lua"

if [ ! -f "$LUA_SOURCE" ]; then
    echo "Error: juggler_wezterm.lua not found at $LUA_SOURCE"
    exit 1
fi

mkdir -p "$WEZTERM_CONFIG_DIR"

cp "$LUA_SOURCE" "$LUA_DEST"
echo "Installed Lua snippet to $LUA_DEST"

if [ ! -f "$WEZTERM_CONFIG_LUA" ]; then
    # Create a minimal wezterm.lua that loads our snippet.
    cat > "$WEZTERM_CONFIG_LUA" <<EOF
local wezterm = require 'wezterm'
$REQUIRE_LINE
return {}
EOF
    echo "Created $WEZTERM_CONFIG_LUA with require directive"
elif ! grep -qF "juggler_wezterm" "$WEZTERM_CONFIG_LUA"; then
    echo "" >> "$WEZTERM_CONFIG_LUA"
    echo "$REQUIRE_LINE" >> "$WEZTERM_CONFIG_LUA"
    echo "Added require directive to $WEZTERM_CONFIG_LUA"
else
    echo "Require directive already present in $WEZTERM_CONFIG_LUA"
fi

echo ""
echo "WezTerm Lua integration installed successfully!"
echo "Restart WezTerm (or trigger a config reload) for changes to take effect."

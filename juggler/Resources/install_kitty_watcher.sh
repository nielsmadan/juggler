#!/bin/bash
# Installs Juggler watcher for Kitty terminal
# Idempotent - safe to run multiple times

set -e

# Resolve kitty config directory following kitty's search order:
# 1. $KITTY_CONFIG_DIRECTORY (exclusive override)
# 2. $XDG_CONFIG_HOME/kitty
# 3. ~/.config/kitty (default)
if [ -n "$KITTY_CONFIG_DIRECTORY" ]; then
    KITTY_CONFIG_DIR="$KITTY_CONFIG_DIRECTORY"
elif [ -n "$XDG_CONFIG_HOME" ]; then
    KITTY_CONFIG_DIR="$XDG_CONFIG_HOME/kitty"
else
    KITTY_CONFIG_DIR="$HOME/.config/kitty"
fi
WATCHER_DEST="$KITTY_CONFIG_DIR/juggler_watcher.py"
KITTY_CONF="$KITTY_CONFIG_DIR/kitty.conf"
# Use tilde path when possible for portability in dotfiles
WATCHER_LINE="watcher ${KITTY_CONFIG_DIR/#$HOME/\~}/juggler_watcher.py"

# Get the watcher source from the app bundle
SCRIPT_DIR="$(dirname "$0")"
WATCHER_SOURCE="$SCRIPT_DIR/juggler_watcher.py"

if [ ! -f "$WATCHER_SOURCE" ]; then
    echo "Error: juggler_watcher.py not found at $WATCHER_SOURCE"
    exit 1
fi

mkdir -p "$KITTY_CONFIG_DIR"

cp "$WATCHER_SOURCE" "$WATCHER_DEST"
echo "Installed watcher to $WATCHER_DEST"

# Add watcher directive to kitty.conf if not already present
if [ ! -f "$KITTY_CONF" ]; then
    echo "$WATCHER_LINE" > "$KITTY_CONF"
    echo "Created $KITTY_CONF with watcher directive"
elif ! grep -qF "juggler_watcher.py" "$KITTY_CONF"; then
    echo "" >> "$KITTY_CONF"
    echo "$WATCHER_LINE" >> "$KITTY_CONF"
    echo "Added watcher directive to $KITTY_CONF"
else
    echo "Watcher directive already present in $KITTY_CONF"
fi

echo ""
echo "Kitty watcher installed successfully!"
echo "Restart Kitty for changes to take effect."

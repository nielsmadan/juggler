#!/bin/bash
# Installs Juggler watcher for Kitty terminal
# Idempotent - safe to run multiple times

set -e

KITTY_CONFIG_DIR="$HOME/.config/kitty"
WATCHER_DEST="$KITTY_CONFIG_DIR/juggler_watcher.py"
KITTY_CONF="$KITTY_CONFIG_DIR/kitty.conf"
WATCHER_LINE="watcher ~/.config/kitty/juggler_watcher.py"

# Get the watcher source from the app bundle
SCRIPT_DIR="$(dirname "$0")"
WATCHER_SOURCE="$SCRIPT_DIR/juggler_watcher.py"

if [ ! -f "$WATCHER_SOURCE" ]; then
    echo "Error: juggler_watcher.py not found at $WATCHER_SOURCE"
    exit 1
fi

# Create config directory if needed
mkdir -p "$KITTY_CONFIG_DIR"

# Copy watcher script
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

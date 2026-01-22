#!/bin/bash
# Add session to queue when Claude waits for input

SCRIPT_DIR="$(dirname "$0")"
PYTHON3="$(pyenv which python3 2>/dev/null || command -v python3)"

# Add to queue
[ -n "$ITERM_SESSION_ID" ] && "$PYTHON3" "$SCRIPT_DIR/session_queue.py" add "$ITERM_SESSION_ID"

# Send notification with click-to-activate
if command -v terminal-notifier &>/dev/null && [ -n "$ITERM_SESSION_ID" ]; then
    ESCAPED_SCRIPT="$(printf '%q' "$SCRIPT_DIR/activate_iterm_session.py")"
    ESCAPED_SESSION_ID="$(printf '%q' "$ITERM_SESSION_ID")"
    terminal-notifier \
        -title "Claude Code" \
        -message "Waiting for input" \
        -sound Glass \
        -execute "$PYTHON3 $ESCAPED_SCRIPT $ESCAPED_SESSION_ID"
elif command -v terminal-notifier &>/dev/null; then
    terminal-notifier \
        -title "Claude Code" \
        -message "Waiting for input" \
        -sound Glass \
        -activate com.googlecode.iterm2
else
    osascript -e 'display notification "Waiting for input" with title "Claude Code" sound name "Glass"'
fi

echo -e "\a"

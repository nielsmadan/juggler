#!/bin/bash
# Add session to queue when Claude starts
SCRIPT_DIR="$(dirname "$0")"
PYTHON3="$(pyenv which python3 2>/dev/null || command -v python3)"

[ -n "$ITERM_SESSION_ID" ] && "$PYTHON3" "$SCRIPT_DIR/session_queue.py" add "$ITERM_SESSION_ID"

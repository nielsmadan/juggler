#!/bin/bash
# Remove session from queue when user submits input

echo "$(date): on_prompt_submit fired, ITERM_SESSION_ID=$ITERM_SESSION_ID" >> /tmp/hook_debug.log

SCRIPT_DIR="$(dirname "$0")"
PYTHON3="$(pyenv which python3 2>/dev/null || command -v python3)"

[ -n "$ITERM_SESSION_ID" ] && "$PYTHON3" "$SCRIPT_DIR/session_queue.py" remove "$ITERM_SESSION_ID"

echo "$(date): on_prompt_submit done" >> /tmp/hook_debug.log

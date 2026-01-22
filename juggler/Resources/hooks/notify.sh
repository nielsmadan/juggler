#!/bin/bash
# Juggler hook script for Claude Code
# Posts hook events to Juggler using unified payload format

EVENT="$1"
JUGGLER_PORT="${JUGGLER_PORT:-7483}"

# Read raw JSON input from stdin (Claude Code passes hook data via stdin)
HOOK_INPUT=$(cat)

# Get iTerm session ID from environment (if available)
ITERM_SESSION_ID="${ITERM_SESSION_ID:-}"

# Get tmux pane ID and session name (if running inside tmux)
TMUX_PANE_ID="${TMUX_PANE:-}"
TMUX_SESSION_NAME=""
if [ -n "$TMUX_PANE_ID" ] && command -v tmux >/dev/null 2>&1; then
    TMUX_SESSION_NAME=$(tmux display-message -p -t "$TMUX_PANE_ID" '#{session_name}' 2>/dev/null || echo "")
fi

# Get git info (if in a git repo)
GIT_BRANCH=$(git -C "$PWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
GIT_REPO=$(basename "$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")

# Pass all data safely via environment variables (avoids shell injection in heredoc)
export JUGGLER_HOOK_INPUT="$HOOK_INPUT"
export JUGGLER_EVENT="$EVENT"
export JUGGLER_ITERM_SID="$ITERM_SESSION_ID"
export JUGGLER_CWD="$PWD"
export JUGGLER_GIT_BRANCH="$GIT_BRANCH"
export JUGGLER_GIT_REPO="$GIT_REPO"
export JUGGLER_TMUX_PANE="$TMUX_PANE_ID"
export JUGGLER_TMUX_SESSION="$TMUX_SESSION_NAME"

# Build unified payload using Python (quoted heredoc prevents shell expansion)
# Pipe JSON output directly to curl via stdin
python3 << 'PYTHON' | curl -s -X POST "http://localhost:${JUGGLER_PORT}/hook" \
    -H "Content-Type: application/json" \
    -d @- \
    --connect-timeout 1 \
    >/dev/null 2>&1 || true
import json
import os

# Parse hook input from environment (safe - no shell interpolation)
# Only extract fields Juggler needs; raw hookInput can be very large
# (e.g. PostToolUse includes full tool_input/tool_result)
hook_input = {}
raw = os.environ.get("JUGGLER_HOOK_INPUT", "")
if raw.strip():
    try:
        full = json.loads(raw)
        for key in ("session_id", "transcript_path", "tool_name"):
            if key in full:
                hook_input[key] = full[key]
    except json.JSONDecodeError:
        pass

payload = {
    "agent": "claude-code",
    "event": os.environ.get("JUGGLER_EVENT", ""),
    "hookInput": hook_input,
    "terminal": {
        "sessionId": os.environ.get("JUGGLER_ITERM_SID", ""),
        "cwd": os.environ.get("JUGGLER_CWD", "")
    },
    "git": {
        "branch": os.environ.get("JUGGLER_GIT_BRANCH", ""),
        "repo": os.environ.get("JUGGLER_GIT_REPO", "")
    }
}

tmux_pane = os.environ.get("JUGGLER_TMUX_PANE", "")
tmux_session = os.environ.get("JUGGLER_TMUX_SESSION", "")
if tmux_pane:
    tmux_info = {"pane": tmux_pane}
    if tmux_session:
        tmux_info["sessionName"] = tmux_session
    payload["tmux"] = tmux_info

print(json.dumps(payload))
PYTHON

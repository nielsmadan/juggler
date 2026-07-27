#!/bin/bash
# Juggler hook script for the Antigravity CLI (agy)
# Posts hook events to Juggler using the unified payload format, then emits the
# hook response Antigravity reads from stdout.
# Antigravity passes hook data via stdin as JSON (camelCase); the event name is argv[1].
#
# stdout contract (Antigravity reads it):
#   Stop         -> {"decision":"stop"}  — any value other than "continue" allows the
#                   stop; emitting "continue" would trap the agent back into its loop.
#   PreInvocation-> {}                    — output is optional; {} is the safe no-op.
# The response is emitted unconditionally, so a failed/slow POST never traps the agent.

EVENT="$1"
JUGGLER_PORT="${JUGGLER_PORT:-7483}"

HOOK_INPUT=$(cat)

# Antigravity runs the hook from its own config dir, not the session's cwd, so $PWD is
# wrong here. The real project directory is in the payload's workspacePaths[0].
WORKSPACE_DIR=$(printf '%s' "$HOOK_INPUT" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    paths = data.get("workspacePaths") if isinstance(data, dict) else None
    print(paths[0] if isinstance(paths, list) and paths else "")
except Exception:
    print("")
' 2>/dev/null)
SESSION_CWD="${WORKSPACE_DIR:-$PWD}"

ITERM_SESSION_ID="${ITERM_SESSION_ID:-}"
KITTY_WINDOW_ID="${KITTY_WINDOW_ID:-}"
KITTY_LISTEN_ON="${KITTY_LISTEN_ON:-}"
KITTY_PID="${KITTY_PID:-}"
WEZTERM_PANE="${WEZTERM_PANE:-}"

if [ -n "$KITTY_WINDOW_ID" ]; then
    TERMINAL_TYPE="kitty"
    TERMINAL_SESSION_ID="$KITTY_WINDOW_ID"
elif [ -n "$ITERM_SESSION_ID" ]; then
    TERMINAL_TYPE="iterm2"
    TERMINAL_SESSION_ID="$ITERM_SESSION_ID"
elif [ -n "$WEZTERM_PANE" ]; then
    TERMINAL_TYPE="wezterm"
    TERMINAL_SESSION_ID="$WEZTERM_PANE"
else
    TERMINAL_TYPE=""
    TERMINAL_SESSION_ID=""
fi

TMUX_PANE_ID="${TMUX_PANE:-}"
TMUX_SESSION_NAME=""
if [ -n "$TMUX_PANE_ID" ] && command -v tmux >/dev/null 2>&1; then
    TMUX_SESSION_NAME=$(tmux display-message -p -t "$TMUX_PANE_ID" '#{session_name}' 2>/dev/null || echo "")
fi

GIT_BRANCH=$(git -C "$SESSION_CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
GIT_REPO=$(basename "$(git -C "$SESSION_CWD" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")

# SSH detection: $SSH_CONNECTION is set by sshd for any interactive ssh session.
REMOTE_HOST=""
if [ -n "${SSH_CONNECTION:-}" ]; then
    REMOTE_USER="${USER:-$(whoami 2>/dev/null)}"
    REMOTE_HOSTNAME="${HOSTNAME:-$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)}"
    # Strip the FQDN suffix from the host only — not the user, which may contain dots.
    REMOTE_HOST="${REMOTE_USER}@${REMOTE_HOSTNAME%%.*}"
fi

# Pass all data safely via environment variables (avoids shell injection in heredoc)
export JUGGLER_HOOK_INPUT="$HOOK_INPUT"
export JUGGLER_EVENT="$EVENT"
export JUGGLER_TERMINAL_SID="$TERMINAL_SESSION_ID"
export JUGGLER_TERMINAL_TYPE="$TERMINAL_TYPE"
export JUGGLER_KITTY_LISTEN_ON="$KITTY_LISTEN_ON"
export JUGGLER_KITTY_PID="$KITTY_PID"
export JUGGLER_CWD="$SESSION_CWD"
export JUGGLER_GIT_BRANCH="$GIT_BRANCH"
export JUGGLER_GIT_REPO="$GIT_REPO"
export JUGGLER_TMUX_PANE="$TMUX_PANE_ID"
export JUGGLER_TMUX_SESSION="$TMUX_SESSION_NAME"
export JUGGLER_REMOTE_HOST="$REMOTE_HOST"

# Build unified payload using Python (quoted heredoc prevents shell expansion).
# curl is bounded so the script always reaches the stdout response below, well
# within the hook timeout.
python3 << 'PYTHON' | curl -s -X POST "http://localhost:${JUGGLER_PORT}/hook" \
    -H "Content-Type: application/json" \
    -d @- \
    --noproxy '*' \
    --connect-timeout 1 \
    --max-time 2 \
    >/dev/null 2>&1 || true
import json
import os

# Antigravity's stdin uses camelCase. Normalize the fields Juggler needs to the
# snake_case keys HookServer decodes (session_id, transcript_path).
hook_input = {}
raw = os.environ.get("JUGGLER_HOOK_INPUT", "")
if raw.strip():
    try:
        full = json.loads(raw)
        if isinstance(full, dict):
            if "conversationId" in full:
                hook_input["session_id"] = full["conversationId"]
            if "transcriptPath" in full:
                hook_input["transcript_path"] = full["transcriptPath"]
    except json.JSONDecodeError:
        pass

terminal_info = {
    "sessionId": os.environ.get("JUGGLER_TERMINAL_SID", ""),
    "cwd": os.environ.get("JUGGLER_CWD", "")
}

terminal_type = os.environ.get("JUGGLER_TERMINAL_TYPE", "")
if terminal_type:
    terminal_info["terminalType"] = terminal_type

kitty_listen_on = os.environ.get("JUGGLER_KITTY_LISTEN_ON", "")
if kitty_listen_on:
    terminal_info["kittyListenOn"] = kitty_listen_on

kitty_pid = os.environ.get("JUGGLER_KITTY_PID", "")
if kitty_pid:
    terminal_info["kittyPid"] = kitty_pid

payload = {
    "agent": "antigravity",
    "event": os.environ.get("JUGGLER_EVENT", ""),
    "hookInput": hook_input,
    "terminal": terminal_info,
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

remote_host = os.environ.get("JUGGLER_REMOTE_HOST", "")
if remote_host:
    payload["remoteHost"] = remote_host

print(json.dumps(payload))
PYTHON

# Emit the response Antigravity reads from stdout. Unconditional — independent of the
# POST above — so Juggler being down never blocks or traps the agent.
case "$EVENT" in
    Stop)
        printf '{"decision":"stop"}\n'
        ;;
    *)
        printf '{}\n'
        ;;
esac

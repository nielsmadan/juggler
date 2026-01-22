# Claude Code Hooks

Juggler integrates with Claude Code via the hooks system, receiving notifications when session state changes.

## Installation

Hooks are installed to `~/.claude/hooks/` by the installation script:

**Files:**
- `~/.claude/hooks/juggler/notify.sh` - Main notification script
- `~/.claude/hooks/juggler/install.sh` - Installation script (bundled in app)

## Hook Script

The `notify.sh` script:

1. Reads JSON from stdin (hook payload from Claude Code)
2. Enriches with terminal info (`$ITERM_SESSION_ID`)
3. Enriches with git info (branch, repo name)
4. Posts to Juggler's HTTP server

```bash
#!/bin/bash
# Read hook input from stdin
HOOK_INPUT=$(cat)

# Get terminal session ID
TERMINAL_SESSION_ID="${ITERM_SESSION_ID:-}"

# Get git info
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
GIT_REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")

# Build unified payload
PAYLOAD=$(jq -n \
  --arg agent "claude-code" \
  --arg event "$CLAUDE_EVENT" \
  --argjson hookInput "$HOOK_INPUT" \
  --arg sessionId "$TERMINAL_SESSION_ID" \
  --arg cwd "$PWD" \
  --arg gitBranch "$GIT_BRANCH" \
  --arg gitRepo "$GIT_REPO" \
  '{
    agent: $agent,
    event: $event,
    hookInput: $hookInput,
    terminal: {sessionId: $sessionId, cwd: $cwd},
    git: {branch: $gitBranch, repo: $gitRepo}
  }')

# Post to Juggler
curl -s -X POST "http://localhost:7483/hook" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" &
```

## Hook Events

Claude Code fires these events:

| Event | When | Juggler Action |
|-------|------|----------------|
| `SessionStart` | Session begins | Create session (idle) |
| `UserPromptSubmit` | User sends prompt | Set working |
| `PreToolUse` | Before tool execution | Set working |
| `PostToolUse` | After tool execution | Set working |
| `PostToolUseFailure` | Tool failed | Set working |
| `SubagentStart` | Task agent spawned | Set working |
| `SubagentStop` | Task agent finished | (ignored) |
| `PermissionRequest` | Needs permission | Set permission |
| `PreCompact` | Context compaction | Set compacting |
| `Stop` | Agent finished | Set idle |
| `SessionEnd` | Session terminated | Remove session |

## Known Quirks

### SubagentStop Fires After Stop

When Claude Code uses subagents (Task tool), the event sequence is:

**Expected:**
```
SubagentStart → [work] → SubagentStop → Stop
```

**Actual:**
```
SubagentStart → [work] → Stop → SubagentStop (5-10 seconds later)
```

The `SubagentStop` event fires **asynchronously after** the main `Stop` event. This is because subagent cleanup happens in a background process.

**Impact:** If `SubagentStop` mapped to working state, it would overwrite the idle state from `Stop`, making sessions appear stuck.

**Solution:** We ignore `SubagentStop` entirely. The `Stop` event correctly indicates when the session becomes idle.

### Backburner State Persistence

When a session is backburnered:
- Most hook events are ignored (state preserved)
- Only `UserPromptSubmit` exits backburner
- This prevents working sessions from being unintentionally un-backburnered

## Configuration

Hooks are configured in Claude Code's settings at `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": ["~/.claude/hooks/juggler/notify.sh"],
    "UserPromptSubmit": ["~/.claude/hooks/juggler/notify.sh"],
    "PreToolUse": ["~/.claude/hooks/juggler/notify.sh"],
    "PostToolUse": ["~/.claude/hooks/juggler/notify.sh"],
    "PostToolUseFailure": ["~/.claude/hooks/juggler/notify.sh"],
    "SubagentStart": ["~/.claude/hooks/juggler/notify.sh"],
    "SubagentStop": ["~/.claude/hooks/juggler/notify.sh"],
    "PermissionRequest": ["~/.claude/hooks/juggler/notify.sh"],
    "PreCompact": ["~/.claude/hooks/juggler/notify.sh"],
    "Stop": ["~/.claude/hooks/juggler/notify.sh"],
    "SessionEnd": ["~/.claude/hooks/juggler/notify.sh"]
  }
}
```

## Debugging

Check if hooks are working:

```bash
# Watch for hook requests
tail -f /tmp/juggler-hooks.log  # If logging enabled

# Test hook manually
echo '{"session_id":"test"}' | ~/.claude/hooks/juggler/notify.sh

# Check if server is running
curl http://localhost:7483/hook -X POST -d '{"agent":"test","event":"ping"}'
```

---

[← Back to Tech Overview](overview.md)

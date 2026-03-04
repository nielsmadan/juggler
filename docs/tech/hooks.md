# Claude Code Hooks

Juggler integrates with Claude Code and OpenCode via hooks, receiving notifications when session state changes.

## Installation

Hooks are installed to `~/.claude/hooks/` by the installation script:

**Files:**
- `~/.claude/hooks/juggler/notify.sh` - Main notification script
- `~/.claude/hooks/juggler/install.sh` - Installation script (bundled in app)

## Hook Script

**File:** `Resources/hooks/notify.sh`

The script:

1. Receives event name as `$1` (command-line argument)
2. Reads JSON from stdin (hook payload from Claude Code)
3. Detects terminal type (`$ITERM_SESSION_ID` for iTerm2, `$KITTY_WINDOW_ID` for Kitty)
4. Detects tmux pane/session if running inside tmux
5. Enriches with git info (branch, repo name)
6. Builds unified payload via Python (avoids shell injection) and posts to Juggler

The script uses `python3` to build JSON safely via environment variables, piping directly to `curl`. It selectively extracts only needed fields from hookInput (`session_id`, `transcript_path`, `tool_name`) to keep payloads small.

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

Hooks are configured in Claude Code's settings at `~/.claude/settings.json`. The install script (`install.sh`) writes hooks in the nested format with `type`, `command`, `timeout`, and optional `matcher`:

```json
{
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/juggler/notify.sh SessionStart", "timeout": 5}]}],
    "PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "~/.claude/hooks/juggler/notify.sh PreToolUse", "timeout": 5}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/juggler/notify.sh Stop", "timeout": 5}]}]
  }
}
```

**Note:** `SubagentStop` is intentionally **not** hooked — it fires asynchronously after `Stop` and would overwrite the idle state. The install script removes any existing `SubagentStop` hooks.

## Debugging

Check if hooks are working:

```bash
# Watch for hook requests
# Use the in-app log viewer (Settings > Logs) to monitor hook events

# Test hook manually
echo '{"session_id":"test"}' | ~/.claude/hooks/juggler/notify.sh SessionStart

# Check if server is running
curl http://localhost:7483/hook -X POST -d '{"agent":"test","event":"ping"}'
```

---

[← Back to Tech Overview](overview.md)

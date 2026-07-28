# Hook Server

The HookServer is an HTTP server running on `localhost:7483` that receives state change notifications from Claude Code, OpenCode, Codex, Pi, and Antigravity hooks.

## Implementation

**File:** `Services/HookServer.swift`

- Swift actor for thread safety
- Network framework-based HTTP server
- Parses incoming JSON payloads
- Updates SessionManager with new state

## Unified API

All hooks use a single endpoint with a unified payload format:

### Endpoint

```
POST /hook
```

### Request Body

```json
{
  "agent": "claude-code",
  "event": "PreToolUse",
  "hookInput": {
    "session_id": "abc123",
    "transcript_path": "~/.claude/projects/.../session.jsonl",
    "tool_name": "Bash"
  },
  "terminal": {
    "sessionId": "w0t0p0:UUID",
    "cwd": "/Users/name/project"
  },
  "git": {
    "branch": "main",
    "repo": "project-name"
  }
}
```

### Response

```json
{"status": "ok"}
```

Or on error:
```json
{"status": "error", "message": "Invalid JSON"}
```

## Event Types

| Event | Mapped State | Description |
|-------|--------------|-------------|
| `SessionStart` | `idle` | New session started |
| `Stop` | `idle` | Agent finished, waiting for input |
| `StopFailure` | `idle` | Turn ended with an API error |
| `UserPromptSubmit` | `working` | User submitted prompt |
| `PreToolUse` | `working` | About to use a tool |
| `PostToolUse` | `working` | Just used a tool |
| `PostToolUseFailure` | `working` | Tool use failed |
| `SubagentStart` | `working` | Started a subagent |
| `SubagentStop` | (ignored) | Subagent finished |
| `PermissionRequest` | `permission` | Needs user permission |
| `PreCompact` | `compacting` | Context compaction |
| `SessionEnd` | (removed) | Session terminated |

## Event Mapping

`HookEventMapper.map(event:agent:)` (`Models/HookEventMapper.swift`) converts each event to a `MappedAction`, dispatching to per-agent mappers (`mapClaudeCode` / `mapOpenCode` / `mapCodex` / `mapPi` / `mapAntigravity`) by the `agent` parameter. The Claude Code mapping is the Event Types table above; the other agents map as follows (canonical source: `HookEventMapper.swift`).

OpenCode:

| Event | Mapped State |
|-------|--------------|
| `session.created`, `session.status.idle`, `session.idle`, `session.error` | `idle` |
| `session.status.busy`, `session.status.retry` | `working` |
| `permission.asked` | `permission` |
| `session.compacted` | `compacting` |
| `session.deleted`, `server.instance.disposed` | (removed) |

Codex:

| Event | Mapped State |
|-------|--------------|
| `SessionStart`, `Stop` | `idle` |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostCompact` | `working` |
| `PermissionRequest` | `permission` |
| `PreCompact` | `compacting` |
| `SessionEnd` | *(removed)* |

Codex hooks register under `~/.codex/hooks.json` and require `features.hooks = true`
in `~/.codex/config.toml`. Juggler registers nine hook events - `SessionStart`,
`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PreCompact`, `PostCompact`,
`PermissionRequest`, `Stop`, `SessionEnd`. `SessionEnd` removes the session; before
it existed, that relied on terminal bridge cleanup at window close.

Codex gates user-installed hooks behind a trust review (`/hooks` in its TUI).
`CodexHooksInstaller` writes `[hooks.state."<hooksJSONPath>:<event>:<groupIndex>:0"]`
trust entries to `config.toml` directly - a `trusted_hash` (SHA-256 of Codex's
canonical hook fingerprint) - so the hooks run without manual review. The
`<groupIndex>` is resolved at install time from `hooks.json` (it is not always
`0` - a user's preexisting hook for the same event pushes Juggler's group to a
higher index). See [Codex Hooks](codex-hooks.md) for the full mechanism.
Requires Codex CLI ≥ v0.114; `SessionEnd` additionally requires ≥ v0.145.

Pi:

| Event | Mapped State |
|-------|--------------|
| `session_start`, `agent_settled`, `session_compact_idle` | `idle` |
| `agent_start`, `session_compact_working` | `working` |
| `session_before_compact` | `compacting` |
| `session_shutdown` | (removed) |

Pi integrates via a TypeScript extension (like OpenCode), not shell hooks — no
trust step, no feature flag. Pi has no native permission event, so no `permission`
state is produced. The `session_compact_idle`/`session_compact_working` split is
synthesized by the extension from Pi's `session_compact` `reason`. Only a real
`quit` removes the session (new/resume/reload/fork keep the terminal session). See
[Pi Extension](pi-extension.md) for the full mechanism.

Antigravity:

| Event | Mapped State |
|-------|--------------|
| `PreInvocation` | `working` |
| `Stop` | `idle` |

Antigravity (agy) registers shell hooks under a `"juggler"` key in
`~/.gemini/config/hooks.json` — no trust step, no feature flag. Only two of its five
events are registered; it has no session-start/end, permission, or compaction event,
so a session first appears as `working` and is removed via terminal-bridge cleanup.
`Stop` requires the hook to return a `decision`, so the notify script always emits an
allow. See [Antigravity Hooks](antigravity-hooks.md) for the full mechanism.

## Backburner Protection

When a session is backburnered, most events are ignored to preserve the backburner state. Only `UserPromptSubmit` will exit backburner (indicating explicit user action). Antigravity has no `UserPromptSubmit`; a backburnered Antigravity session instead exits on its next `working` event, but only if it was awaiting the user when backburnered (`Session.wasAwaitingUserBeforeBackburner`) — see [Antigravity Hooks](antigravity-hooks.md).

## Testing with curl

```bash
# Simulate session start
curl -X POST "http://localhost:7483/hook" \
  -H "Content-Type: application/json" \
  -d '{
    "agent": "claude-code",
    "event": "SessionStart",
    "terminal": {"sessionId": "test123", "cwd": "/tmp"},
    "hookInput": {"session_id": "abc123"}
  }'

# Simulate idle
curl -X POST "http://localhost:7483/hook" \
  -H "Content-Type: application/json" \
  -d '{
    "agent": "claude-code",
    "event": "Stop",
    "terminal": {"sessionId": "test123", "cwd": "/tmp"},
    "hookInput": {"session_id": "abc123"}
  }'
```

## Kitty Event Endpoint

```
POST /kitty-event
```

Receives events from the Kitty watcher script (`juggler_watcher.py`):

```json
{"event": "focus_changed", "window_id": "123"}
```

```json
{"event": "session_terminated", "window_id": "123"}
```

| Event | Action |
|-------|--------|
| `focus_changed` | Update focused session tracking |
| `session_terminated` | Remove session from SessionManager |

---

[← Back to Tech Overview](overview.md)

# Hook Server

The HookServer is an HTTP server running on `localhost:7483` that receives state change notifications from Claude Code hooks.

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

The `HookEventMapper` (`Models/HookEventMapper.swift`) converts events to actions:

```swift
static func map(event: String) -> MappedAction {
    switch event {
    case "SessionStart", "Stop":
        return .updateState(.idle)
    case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "SubagentStart":
        return .updateState(.working)
    case "SubagentStop":
        return .ignore
    case "PermissionRequest":
        return .updateState(.permission)
    case "PreCompact":
        return .updateState(.compacting)
    case "SessionEnd":
        return .removeSession
    default:
        return .ignore
    }
}
```

## Backburner Protection

When a session is backburnered, most events are ignored to preserve the backburner state. Only `UserPromptSubmit` will exit backburner (indicating explicit user action).

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

---

[← Back to Tech Overview](overview.md)

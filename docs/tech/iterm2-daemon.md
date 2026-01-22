# iTerm2 Daemon

The Python daemon maintains a persistent connection to iTerm2 for fast session activation and highlighting.

## Why a Daemon?

Starting a new Python process for each command takes ~1000ms. A persistent daemon reduces latency to ~50ms by keeping the iTerm2 connection open.

## Implementation

**File:** `Resources/iterm2_daemon.py`

- Python script using iTerm2's Python API
- Runs as subprocess of Juggler.app
- Communicates via Unix socket

**Bridge:** `Services/ITerm2Bridge.swift`

- Swift actor for thread-safe daemon communication
- Handles connection, reconnection, timeouts
- Event listener for focus changes

## Socket Protocol

**Socket path:** `/tmp/juggler-iterm2.sock`

Communication is newline-delimited JSON.

### Commands

**Ping:**
```json
{"command": "ping"}
```

**Activate session:**
```json
{"command": "activate", "session_id": "w0t0p0:UUID"}
```

**Highlight tab/pane:**
```json
{
  "command": "highlight",
  "session_id": "w0t0p0:UUID",
  "tab": {
    "enabled": true,
    "color": [255, 165, 0],
    "duration": 2.0
  },
  "pane": {
    "enabled": true,
    "color": [255, 165, 0],
    "duration": 2.0
  }
}
```

**Reset highlight:**
```json
{"command": "reset", "session_id": "w0t0p0:UUID"}
```

**List all sessions:**
```json
{"command": "list"}
```

**Get session info:**
```json
{"command": "get_session_info", "session_id": "w0t0p0:UUID"}
```

**Subscribe to events:**
```json
{"command": "subscribe"}
```

### Responses

**Success:**
```json
{"status": "ok"}
```

**List result:**
```json
{
  "status": "ok",
  "sessions": [
    {"session_id": "w0t0p0:UUID", "tab_name": "Tab 1", "window_name": "Window"}
  ]
}
```

**Session info:**
```json
{
  "status": "ok",
  "session_id": "w0t0p0:UUID",
  "tab_name": "project",
  "window_name": "iTerm2",
  "pane_index": 0,
  "pane_count": 2
}
```

**Error:**
```json
{"status": "error", "message": "Session not found"}
```

## Events

After subscribing, the daemon sends events:

**Focus changed:**
```json
{"event": "focus_changed", "session_id": "w0t0p0:UUID"}
```

**Terminal info:**
```json
{
  "event": "terminal_info",
  "session_id": "w0t0p0:UUID",
  "tab_name": "Tab",
  "window_name": "Window",
  "pane_index": 0,
  "pane_count": 1
}
```

## Highlight Configuration

The highlight config supports:

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | bool | Whether to highlight |
| `color` | [r, g, b] | RGB color (0-255) |
| `duration` | float | Seconds to show highlight |

## Connection Recovery

If the socket connection fails, the bridge:
1. Detects stale connection errors
2. Restarts the daemon
3. Retries the command

## Python Environment

Uses iTerm2's bundled Python:
```
~/Library/Application Support/iTerm2/iterm2env/versions/*/bin/python3
```

No user Python installation required.

## Authentication

On first launch, Juggler requests an iTerm2 API cookie via AppleScript:
```applescript
tell application "iTerm2" to request cookie and key for app named "Juggler"
```

This triggers macOS Automation permission dialog.

---

[← Back to Tech Overview](overview.md)

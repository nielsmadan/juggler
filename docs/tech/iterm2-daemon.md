# iTerm2 Daemon

The Python daemon maintains a persistent connection to iTerm2 for fast session activation and highlighting.

## Why a Daemon?

Starting a new Python process for each command takes ~1000ms. A persistent daemon reduces latency to ~50ms by keeping the iTerm2 connection open.

## Implementation

**File:** `Resources/iterm2_daemon.py`

- Python script using iTerm2's Python API
- Runs as subprocess of Juggler.app
- Communicates via Unix socket

**Bridge:** `Services/iTerm2Bridge.swift` (the Swift class is `ITerm2Bridge`, capital I)

- Swift actor for thread-safe daemon communication
- Handles connection, reconnection, timeouts
- Event listener for focus changes

## Socket Protocol

**Socket path:** `~/Library/Application Support/Juggler/iterm2_daemon.sock`

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

## Stale sessions and the empty-string exception

iTerm2's cached app model can return a `Session` object for a UUID whose tab is already gone. Touching it - reading `session.tab`/`tab.window`, or calling `async_activate` - then raises, and the rejection often carries an **empty string** as its message. If that exception escapes `activate_session`, it falls through to the top-level handler in `handle_client`, which serializes `str(e)` → `""`, so the bridge receives `commandFailed("")`. An empty message defeats Juggler's `"session not found"` substring match, so the dead session never gets removed.

Two guards keep this from happening:
- `activate_session` **and** `get_session_info` wrap **all** session access (including `session.tab`/`tab.window`/`async_get_variable`, not just the `async_activate` calls) in the try block. On any exception they re-query `get_session_by_id`; if the session is now absent they return the clean `"Session not found"`, otherwise a non-empty `TypeName: message`. `get_session_info` matters because the Swift `isSessionGone` fallback routes its confirmation through it - an unguarded raise there would surface as an opaque error rather than a clean absence signal.
- The `handle_client` fallback uses `str(e) or type(e).__name__`, so even an exception that slips past `activate_session` yields a non-empty, identifiable message instead of `""`.

The Swift side (`TerminalActivation.isSessionGone`) is the belt-and-suspenders layer: it confirms absence via `getSessionInfo` regardless of the message, covering daemons that predate these guards.

## Zombie daemon prevention

The daemon binds a unique temporary socket beside `iterm2_daemon.sock`, makes it ready to accept connections, then atomically replaces the shared path. Concurrent launches can each bind successfully; the last publication owns the path. A `.lock` sidecar serializes publication with cleanup, and the publishing daemon writes its PID to `.pid` under the same lock. The lock file stays in place so every process locks the same inode.

`_monitor_socket_ownership` polls the socket path's inode every 5s against the inode recorded at publication. If they differ or the path is gone, the daemon exits via `stop(unlink=False)`. Normal shutdown also checks ownership under the lock before removing the socket and PID, so retiring daemons preserve the replacement's files.

SIGTERM and SIGINT are handled on the asyncio loop after synchronous publication/cleanup completes. They call `stop()` followed by `os._exit(0)`, which bypasses the iTerm2 library's reconnect wrapper.

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

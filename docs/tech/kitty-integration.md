# Kitty Integration

Juggler integrates with Kitty via the `kitten @` CLI (for commands) and a Python watcher (for events).

## Architecture

```
Juggler ──(kitten @ <cmd> --to unix:<socket>)──→ Kitty remote control API
Kitty   ──(juggler_watcher.py)──────HTTP POST──→ http://localhost:7483/kitty-event
```

Two channels:
- **Outbound commands** — `KittyBridge` invokes `kitten @` to activate windows, set colors, query state.
- **Inbound events** — `juggler_watcher.py` (a Kitty watcher script) posts focus and close events to Juggler's HTTP server.

## Required Kitty Config

`~/.config/kitty/kitty.conf` must contain:

```conf
allow_remote_control socket-only
listen_on unix:/tmp/kitty-{kitty_pid}
watcher /path/to/juggler_watcher.py
```

`Models/ConfigValidator.swift:63` parses the file and reports which directives are present. Validation accepts `yes` or `socket` for `allow_remote_control` (`ConfigValidator.swift:42`).

## Socket Discovery

GUI apps launched from Finder or the Dock do not inherit Kitty's `KITTY_LISTEN_ON` environment variable. Without a socket, `kitten @` hangs.

`KittyBridge.discoverKittySocket()` (`Services/KittyBridge.swift:77-91`) scans `/tmp` for files matching `kitty-*` and uses the first match, formatted as `unix:/tmp/kitty-<pid>`. If none is found, the bridge reports an error telling the user to set `listen_on` and restart Kitty.

## Watcher Installation

`Resources/install_kitty_watcher.sh`:

1. Resolves config dir via `$KITTY_CONFIG_DIRECTORY` → `$XDG_CONFIG_HOME/kitty` → `~/.config/kitty`.
2. Copies `juggler_watcher.py` to `<config>/juggler_watcher.py`.
3. Appends a `watcher` directive to `kitty.conf` if missing (idempotent).
4. Tells the user to restart Kitty.

## Watcher Script

`Resources/juggler_watcher.py` registers two Kitty hooks:

| Hook | HTTP event | Payload |
|------|------------|---------|
| `on_focus_change` | `focus_changed` | `{"event":"focus_changed","window_id":"<id>"}` |
| `on_close` | `session_terminated` | `{"event":"session_terminated","window_id":"<id>"}` |

Posts to `http://localhost:7483/kitty-event` with a 1 s curl timeout. Fire-and-forget: if Juggler isn't running, the watcher silently drops the event.

## Setup UI Flow

`Views/KittySetupView.swift` walks the user through a four-step wizard:

1. **Remote Control** — appends `allow_remote_control socket-only` if missing.
2. **Listen Socket** — appends `listen_on unix:/tmp/kitty-{kitty_pid}` if missing.
3. **Watcher Install** — calls `ScriptInstaller.installKittyWatcher()`.
4. **Test Connection** — runs `KittyBridge.testConnection()`; on success, "Done" enables.

An orange warning reminds the user to restart Kitty after each config change.

## Bridge Operations

All methods on `KittyBridge` (an actor):

| Method | Kitten command | Purpose |
|--------|----------------|---------|
| `activate(sessionID:)` | `focus-window --match id:<id>` + AppleScript `activate` | Focus window and app |
| `highlight(sessionID:tabConfig:paneConfig:)` | `set-tab-color`, `set-colors` | Flash tab/pane for `duration` seconds, then auto-reset |
| `getSessionInfo(sessionID:)` | `ls` (parses JSON output) | Query window metadata |
| `testConnection()` | `ls` | Verify Kitty + socket + kitten are reachable |

## Kitten Binary Resolution

Search order (`KittyBridge.swift:30-53`):

1. App bundle Resources
2. `/usr/local/bin` (Intel Homebrew)
3. `/opt/homebrew` (Apple Silicon Homebrew)
4. `$PATH`

A warning is logged if not found.

## Gotchas

- **GUI env inheritance** — `KITTY_LISTEN_ON` is not inherited by GUI-launched apps; rely on the `/tmp` scan instead (`KittyBridge.swift:71-72`).
- **Kitty restart required** — config edits don't take effect until Kitty is restarted.
- **Pipe drain on detached tasks** — `runKittenCommand` drains stdout/stderr pipes to prevent buffer-full deadlock (`KittyBridge.swift:301`).
- **Highlight reset auto-cancels** — scheduling a new highlight on the same session cancels the pending reset task (`KittyBridge.swift:149, 172`).
- **Missing window maps to `connectionFailed`** — if a window ID is unknown, the bridge returns `connectionFailed` rather than `sessionNotFound` to avoid an infinite cleanup cycle (`KittyBridge.swift:114-115`).

## Concurrency

`KittyBridge` is a Swift actor. Reset tasks are keyed by sessionID in `activeTabResetTasks` / `activePaneResetTasks`. Kitten commands use `withCheckedThrowingContinuation` with a 5 s timeout. JSON parsing (`parseKittyLsOutput`) is `nonisolated`.

---

[← Back to Tech Overview](overview.md)

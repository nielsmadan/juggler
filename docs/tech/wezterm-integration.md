# WezTerm Integration

Juggler integrates with WezTerm via the `wezterm cli` (for commands) and a Lua snippet (for events).

## Architecture

```
Juggler ──(wezterm cli <cmd>)────────────────────► WezTerm GUI
WezTerm ──(juggler_wezterm.lua → curl POST)──────► http://localhost:7483/wezterm-event
```

Two channels:
- **Outbound commands** — `WezTermBridge` invokes `wezterm cli` to activate panes, list state, and push tab colors.
- **Inbound events** — `juggler_wezterm.lua` (registered via the user's `wezterm.lua`) posts focus events to Juggler's HTTP server.

## Required WezTerm Config

`~/.config/wezterm/wezterm.lua` (or `$WEZTERM_CONFIG_FILE`) must contain:

```lua
require 'juggler_wezterm'
```

The installer (`install_wezterm_lua.sh`) adds this line idempotently and copies `juggler_wezterm.lua` next to `wezterm.lua`.

`Models/WezTermConfigValidator.swift` resolves the config path and reports installation status.

## GUI Discovery

Unlike Kitty, WezTerm's `wezterm cli` auto-discovers a running GUI — no Unix socket scan required. `Services/WezTermBridge.swift` only needs to locate the `wezterm` binary, which it probes in this order:

1. `/Applications/WezTerm.app/Contents/MacOS/wezterm`
2. `/usr/local/bin/wezterm` (Intel Homebrew)
3. `/opt/homebrew/bin/wezterm` (Apple Silicon Homebrew)
4. `wezterm` via `$PATH`

A warning is logged if not found.

## Lua Snippet

`Resources/juggler_wezterm.lua` registers two events:

| Event | HTTP event | Payload |
|-------|------------|---------|
| `window-focus-changed` | `focus_changed` | `{"event":"focus_changed","pane_id":"<id>"}` |
| `format-tab-title` | (none — local) | reads `pane.user_vars.juggler_color` and colors the tab |

Posts to `http://localhost:7483/wezterm-event` with a 1s curl timeout. Fire-and-forget via `wezterm.background_child_process` — if Juggler isn't running, the request is silently dropped.

## Setup UI Flow

`Views/WezTermSetupView.swift` walks the user through a two-step wizard:

1. **Install Lua Snippet** — `ScriptInstaller.installWezTermLua()` runs the bundled `install_wezterm_lua.sh`.
2. **Test Connection** — `WezTermBridge.testConnection()` runs `wezterm cli list --format json`; on success, "Done" enables.

An orange warning reminds the user to restart WezTerm after the Lua install.

## Bridge Operations

All methods on `WezTermBridge` (an actor):

| Method | wezterm cli | Purpose |
|--------|----------------|---------|
| `activate(sessionID:)` | `cli activate-pane --pane-id <id>` + AppleScript `activate` | Focus pane and app |
| `highlight(sessionID:tabConfig:paneConfig:)` | `cli send-text --pane-id <id> --no-paste` (OSC `SetUserVar`) | Flash tab via user var for `duration` seconds, then auto-reset. Pane background is **not supported**. |
| `getSessionInfo(sessionID:)` | `cli list --format json` | Query pane metadata |
| `testConnection()` | `cli list --format json` | Verify wezterm binary + GUI reachable |
| `reconcile()` (internal, every 30s) | `cli list --format json` | Detect closed panes (no `on_close` event exists) |

## Tab Coloring via `SetUserVar`

WezTerm has no runtime CLI for tab/pane colors. Juggler sets a per-pane user var:

```
ESC ] 1337 ; SetUserVar = juggler_color = <base64(hex)> BEL
```

The Lua `format-tab-title` handler reads this user var and renders the tab background accordingly.

## Pane Closure Detection

WezTerm has no `on_close` event. Two layers handle this:

1. **Agent hook scripts** post a session-end signal when the agent exits — immediate.
2. **`WezTermBridge.reconcile()`** runs every 30s, diffs `wezterm cli list` against tracked pane IDs, and removes orphaned sessions via `SessionManager.removeSessionsByTerminalID(_:)`.

## Gotchas

- **Pane background highlighting is not supported.** `highlight()` silently no-ops the `paneConfig`. The IntegrationSettingsView surfaces this in a footnote.
- **`format-tab-title` is last-write-wins.** If the user's own `wezterm.lua` registers a `format-tab-title` handler after `require 'juggler_wezterm'`, our colors won't render. Users with custom tab-title handlers should read `pane.user_vars.juggler_color` themselves.
- **`wezterm cli send-text` defaults to bracketed paste.** Must pass `--no-paste`, or the OSC escape will be wrapped and not interpreted by the terminal.
- **GUI auto-spawn.** `wezterm cli` against an instance that isn't running may spawn one. Probes use `wezterm cli list --format json` rather than `activate-pane`.
- **tmux + WezTerm.** Juggler's bundled tmux `update-environment` line forwards iTerm2/Kitty env vars but not `WEZTERM_PANE`. tmux users on WezTerm need to add `WEZTERM_PANE` to their own `update-environment` directive.

## Concurrency

`WezTermBridge` is a Swift actor. Tab-color reset tasks are keyed by `sessionID` in `activeTabResetTasks`. CLI calls use `withCheckedThrowingContinuation` with a 5s timeout and pipe drainage. JSON parsing (`parseWezTermListOutput`) is `nonisolated`.

---

[← Back to Tech Overview](overview.md)

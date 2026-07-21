# Technical Overview

Juggler is a SwiftUI menu bar app that tracks Claude Code, OpenCode, Codex (experimental), and Pi sessions via HTTP hooks and provides global hotkeys for navigation. It communicates with iTerm2 through a persistent Python daemon and with Kitty via the `kitten @` CLI.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Juggler.app                              │
├─────────────────────────────────────────────────────────────────┤
│  Swift/SwiftUI - macOS 14+ (Sonoma)                             │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ HookServer  │  │ SessionMgr  │  │ HotkeyManager           │  │
│  │ :7483       │→ │ @Observable │→ │ KeyboardShortcuts       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
│         ↑                │                      │               │
│         │                ↓                      ↓               │
│         │         ┌─────────────┐     ┌──────────────────────┐    │
│         │         │ Views       │     │ TerminalBridgeReg.  │    │
│         │         │ SwiftUI     │     │ ┌────────┐┌───────┐ │    │
│         │         └─────────────┘     │ │iTerm2  ││Kitty  │ │    │
│         │                             │ │Bridge  ││Bridge │ │    │
│         │                             │ └────────┘└───────┘ │    │
└─────────│─────────────────────────────│───────│────────│────────┘
          │                             │       │        │
   HTTP POST                      Unix Socket   │    kitten @
          │                             │       │        │
          ↓                             ↓       ↓        ↓
┌─────────────────┐           ┌──────────────┐    ┌─────────┐
│  Claude Code /  │           │ iterm2_      │    │  Kitty  │
│  OpenCode /     │           │ daemon.py    │    │         │
│  Codex / Pi     │           │ (subprocess) │    └─────────┘
│  Hooks          │           └──────────────┘
│  notify.sh      │
└─────────────────┘                  │
                                     ↓
                                ┌─────────┐
                                │ iTerm2  │
                                └─────────┘
```

## Components

Source is under `juggler/`, grouped by role. `ls` a folder for the full list; the
authoritative annotated map is the tree in [AGENTS.md](../../AGENTS.md). This section is
orientation and entry points, not a per-file inventory (that would drift):

- **`Models/`**: data and pure logic. Entry points: `Session` + `SessionState` (state enum:
  working / idle / permission / backburner / compacting), `CyclingEngine` (cycle order),
  `HookEventMapper` (hook event to state). Also holds the beacon-geometry, stats, and
  config-validation value types.
- **`Managers/`**: `@Observable` app-state controllers, one concern each. `SessionManager`
  is the hub (session list, cycling, actions); the rest own hotkeys, the status-bar popover,
  notifications, the beacon, logging, and Sparkle updates.
- **`Services/`**: I/O. `HookServer` (HTTP :7483, the ingress for every agent hook) plus the
  terminal layer: `TerminalBridge` / `TerminalBridgeRegistry` with `iTerm2Bridge` (Unix
  socket to the Python daemon) and `KittyBridge` (`kitten @` CLI). Agent-integration
  installers also live here.
- **`Views/`**: SwiftUI: menu-bar popover, session-monitor window, settings, onboarding, and
  the stats/beacon UI.

See Topic Documentation below for per-subsystem deep dives, and the code for the exhaustive
file list.

## Dependencies

**Swift Package Manager:**
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - Global hotkeys
- [Sparkle](https://github.com/sparkle-project/Sparkle) - Auto-updates

**Built-in Frameworks:**
- SwiftUI, Network, UserNotifications, ServiceManagement

**iTerm2:**
- Uses iTerm2's bundled Python at `~/Library/Application Support/iTerm2/iterm2env/`

## Storage

| Data | Location | Persistence |
|------|----------|-------------|
| Sessions | In-memory | None (populated by hooks) |
| Settings | `~/Library/Preferences/dev.juggler.Juggler.plist` | @AppStorage |

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | SwiftUI | Declarative, modern, less code |
| App Lifecycle | NSStatusItem + NSPopover | Managed by StatusBarManager; SwiftUI Window scenes for settings/monitor |
| macOS Target | 14+ | @Observable, modern SwiftUI features |
| Global Hotkeys | KeyboardShortcuts | Built-in recorder UI, SwiftUI integration |
| Auto-Updates | Sparkle | Industry standard for non-App Store apps |
| Hook Server | HTTP localhost:7483 | Debuggable with curl, future remote support |
| iTerm2 Integration | Persistent Python daemon | Fast (~50ms vs ~1000ms per-command) |
| Terminal Abstraction | Protocol-based | Clean path to support other terminals |

## Known Platform Limitations

### Notification Click Activation

macOS always brings the posting app to the foreground when a notification banner is clicked. This is system-level behavior with no opt-out API (confirmed via Apple documentation, open-source survey, and [FB13131879](https://github.com/feedback-assistant/reports/issues/418)). The activation is two-phase: once before `didReceive`, once after `completionHandler()`.

Juggler works with this by letting the activation complete, then yielding focus to the terminal via `yieldActivation` + `NSRunningApplication.activate()` after a short settling delay. This causes a brief flash of Juggler before the terminal takes focus. Custom `UNNotificationAction` buttons without `.foreground` can run in the background, but the default banner click cannot be intercepted.

### Beacon Active-Window Positioning

The `.activeWindow` beacon anchor converts the frontmost window's CoreGraphics (top-left origin) frame to AppKit (bottom-left origin) coordinates. The flip must use the **primary** screen height - `NSScreen.screens.first` (`screens[0]`), not `NSScreen.main` (which is the screen holding keyboard focus). Using `NSScreen.main` mispositions the beacon on multi-monitor setups. See `BeaconManager.frontmostWindowFrame()`.

## Recurring gotchas

Distilled from `docs/log/` post-mortems. The full write-ups stay there as the archive; these
are the reusable lessons for anyone working in the affected area.

- **The iTerm2 daemon must run on Python 3.7+.** `iTerm2Bridge` picks iTerm2's bundled Python
  by *lexicographic* sort, which selects `3.8.x` over `3.10`/`3.14`. Keep
  `from __future__ import annotations` at the top of `Resources/iterm2_daemon.py` so modern
  type-hint syntax (`dict[str, Any]`) isn't evaluated at import and crash on 3.8. Don't apply
  system-Python linting/modernization to that file. (`log/2026-02-07-daemon-crash-python-type-hints.md`)
- **Daemon socket reads must be newline-framed.** TCP is a stream, so one `recv()` is not a
  complete message. `iTerm2Bridge.sendRequest()` loops until a trailing `\n`; a `dataCorrupted`
  / "Unexpected end of file" decode error means a truncated read. (`log/2026-01-26-terminal-info-not-updating.md`)
- **No `withThrowingTaskGroup` inside an actor-isolated method when the child closure captures
  `self`**: it deadlocks (parent holds the actor, child needs it, call hangs silently). Use a
  socket-level timeout or cancellable `Task.sleep` instead, and log at method entry before any
  `await` to catch silent hangs. (`log/2026-01-27-actor-deadlock-withTimeout.md`)

## Logging

`LogManager` (`Managers/LogManager.swift`) is an in-app ring buffer (last 500 entries) surfaced in Settings > Logs. Warnings and errors are always captured; `debug`/`info` entries are recorded only when the Verbose Logging setting is on. Per-category compile-time flags also gate `print` output to Xcode. `exportAll()` backs the copy/export control.

## Topic Documentation

- [Hook Server](hook-server.md) - HTTP API for hooks
- [Claude Code Hooks](hooks.md) - Shell hook integration and payload contract
- [OpenCode Plugin](opencode-plugin.md) - TypeScript plugin integration
- [Codex Hooks](codex-hooks.md) - Codex hook integration and trust mechanism
- [Pi Extension](pi-extension.md) - Pi TypeScript extension integration
- [iTerm2 Daemon](iterm2-daemon.md) - Python daemon protocol
- [iTerm2 Bridge](iterm2-bridge.md) - Daemon supervisor lifecycle, auto-recovery, and self-healing monitors
- [Kitty Integration](kitty-integration.md) - Kitten CLI and watcher
- [Terminal Bridges](terminal-bridges.md) - Bridge protocol and how to add a terminal
- [Session Management](session-management.md) - Cycling and state logic
- [Busy-Time Stats](stats.md) - Per-session accrual, DailyStatsStore persistence, chart + corner-tab layout
- [Session Highlight Color](highlight-color.md) - Where the highlight-color rules are implemented

---

[← Back to Overview](../overview.md)

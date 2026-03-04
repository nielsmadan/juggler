# Technical Overview

Juggler is a SwiftUI menu bar app that tracks Claude Code and OpenCode sessions via HTTP hooks and provides global hotkeys for navigation. It communicates with iTerm2 through a persistent Python daemon and with Kitty via the `kitten @` CLI.

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
│  OpenCode       │           │ daemon.py    │    │         │
│  Hooks          │           │ (subprocess) │    └─────────┘
│  notify.sh      │           └──────────────┘
└─────────────────┘                  │
                                     ↓
                                ┌─────────┐
                                │ iTerm2  │
                                └─────────┘
```

## Components

### Models

| Model | File | Purpose |
|-------|------|---------|
| `Session` | `Models/Session.swift` | Session data (ID, state, path, timestamps) |
| `SessionState` | `Models/SessionState.swift` | State enum (working, idle, permission, backburner) |
| `LocalShortcut` | `Models/LocalShortcut.swift` | In-app keyboard shortcuts |
| `CyclingEngine` | `Models/CyclingEngine.swift` | Session cycling logic |
| `HookEventMapper` | `Models/HookEventMapper.swift` | Hook event → state mapping |

### Managers

| Manager | File | Purpose |
|---------|------|---------|
| `SessionManager` | `Managers/SessionManager.swift` | @Observable session list, cycling, actions |
| `HotkeyManager` | `Managers/HotkeyManager.swift` | Global hotkeys via KeyboardShortcuts |
| `StatusBarManager` | `Managers/StatusBarManager.swift` | NSStatusItem + NSPopover management |
| `NotificationManager` | `Managers/NotificationManager.swift` | macOS notifications |
| `BeaconManager` | `Managers/BeaconManager.swift` | Beacon overlay for session cycling |
| `LogManager` | `Managers/LogManager.swift` | In-app logging system |
| `UpdateManager` | `Managers/UpdateManager.swift` | Sparkle auto-updates |

### Services

| Service | File | Purpose |
|---------|------|---------|
| `HookServer` | `Services/HookServer.swift` | HTTP server on :7483 (`/hook`, `/kitty-event`) |
| `iTerm2Bridge` | `Services/iTerm2Bridge.swift` | Daemon communication (Unix socket) |
| `KittyBridge` | `Services/KittyBridge.swift` | Kitty integration via `kitten @` CLI |
| `TerminalBridge` | `Services/TerminalBridge.swift` | Terminal abstraction protocol |
| `TerminalBridgeRegistry` | `Services/TerminalBridgeRegistry.swift` | Bridge registration and lifecycle |

### Views

| View | Purpose |
|------|---------|
| `MenuBarView` | Menu bar popover |
| `SessionMonitorView` | Main window |
| `SessionRowView` | Session row component |
| `SettingsView` | Preferences window |
| `OnboardingView` | First-launch wizard |

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

## Topic Documentation

- [Hook Server](hook-server.md) - HTTP API for hooks
- [iTerm2 Daemon](iterm2-daemon.md) - Python daemon protocol
- [Session Management](session-management.md) - Cycling and state logic
- [Claude Code Hooks](hooks.md) - Hook integration

---

[← Back to Overview](../overview.md)

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
just build    # Build the app
just run      # Build and run
just test     # Run unit tests only (fast, no UI)
just test-ui  # Run UI tests only (launches app)
just test-all # Run all tests (unit + UI)
just clean    # Remove build directory
just lint     # Run SwiftLint
just format       # Run SwiftFormat
just unused-check # Check for unused code (Periphery)
just coverage     # Run tests and print coverage summary
just reset-all    # Clear all app preferences (for testing fresh state)
```

Or use Xcode: `⌘B` to build, `⌘R` to run.

**Testing workflow:** Don't run `just run` - the user will run and test the app themselves. Just run `just build` and tell the user when it's ready for testing.

## Testing Hooks

Test hook server manually:
```bash
curl -X POST "http://localhost:7483/session/start" \
  -H "Content-Type: application/json" \
  -d '{"session_id": "test123", "iterm_session_id": "w0t0p0:UUID", "cwd": "/tmp"}'
```

## Architecture

Juggler is a SwiftUI menu bar app (macOS 14+) that tracks Claude Code sessions via hooks and provides global hotkeys to navigate between them.

**Data flow:**
1. Claude Code hooks → HTTP POST to `HookServer` (port 7483)
2. `HookServer` → updates `SessionManager` (in-memory @Observable)
3. Global hotkeys → `HotkeyManager` → `SessionManager.cycleForward/Backward()`
4. Activation → `ITerm2Bridge` → Python daemon (Unix socket) → iTerm2

**Project structure:**
```
Juggler/
├── JugglerApp.swift              # App entry point, MenuBarExtra, Window scenes
├── Managers/
│   ├── HotkeyManager.swift       # Global keyboard shortcuts (KeyboardShortcuts library)
│   ├── NotificationManager.swift # macOS notifications for idle/permission states
│   ├── SessionManager.swift      # Session list, cycling logic (no persistence)
│   ├── StatusBarManager.swift    # Menu bar icon management
│   └── UpdateManager.swift       # Sparkle auto-updates
├── Models/
│   ├── LocalShortcut.swift       # Configurable in-app keyboard shortcuts
│   ├── Session.swift             # Session data model
│   ├── SessionState.swift        # idle, working, permission, backburner, compacting
│   └── TerminalType.swift        # Terminal app abstraction
├── Services/
│   ├── HookServer.swift          # HTTP server receiving Claude Code hooks
│   ├── ITerm2Bridge.swift        # Unix socket communication with Python daemon
│   └── TerminalBridge.swift      # Terminal abstraction protocol
├── Views/
│   ├── AboutView.swift           # About window
│   ├── LocalShortcutRecorderView.swift  # Shortcut recorder for settings
│   ├── MenuBarView.swift         # Menu bar popover
│   ├── OnboardingView.swift      # First-run setup
│   ├── RenameSessionView.swift   # Session rename sheet
│   ├── SessionMonitorView.swift  # Main window session list
│   ├── SessionRowView.swift      # Individual session row
│   └── SettingsView.swift        # Preferences window
└── Resources/
    └── iterm2_daemon.py          # Python daemon for iTerm2 API
```

**Session states:** `idle`, `permission`, `working`, `backburner` (excluded from cycle), `compacting`

**Menu bar app quirks:**
- Uses `.menuBarExtraStyle(.window)` for popover UI
- `OnboardingView` window triggers first-run setup
- During onboarding: `NSApp.setActivationPolicy(.regular)` shows dock icon; `.accessory` hides it when done

## Hook Installation

Hooks are installed to `~/.claude/hooks/juggler/`. The `notify.sh` script reads session data from stdin (JSON) and posts to Juggler's HTTP server.

## Code Style

- SwiftLint and SwiftFormat configured
- 4-space indentation, 120 char max width
- Use @Observable (not ObservableObject) for state
- Use @AppStorage for UserDefaults persistence

## Related Documentation

- [README.md](README.md) - User-facing documentation
- [docs/requirements.md](docs/requirements.md) - Current requirements
- [docs/tech/overview.md](docs/tech/overview.md) - Technical architecture
- [docs/prd/overview.md](docs/prd/overview.md) - Product requirements document

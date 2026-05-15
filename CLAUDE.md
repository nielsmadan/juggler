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
curl -X POST "http://localhost:7483/hook" \
  -H "Content-Type: application/json" \
  -d '{"agent":"claude-code","event":"SessionStart","terminal":{"sessionId":"test123","cwd":"/tmp"},"hookInput":{"session_id":"abc123"}}'
```

## Architecture

Juggler is a SwiftUI menu bar app (macOS 14+) that tracks Claude Code, OpenCode, and Codex sessions via hooks and provides global hotkeys to navigate between them.

**Data flow:**
1. Claude Code / OpenCode / Codex hooks → HTTP POST to `HookServer` (port 7483)
2. `HookServer` → updates `SessionManager` (in-memory @Observable)
3. Global hotkeys → `HotkeyManager` → `SessionManager.cycleForward/Backward()`
4. Activation → `TerminalBridge` (iTerm2Bridge/KittyBridge) → terminal

**Project structure:**
```
Juggler/
├── JugglerApp.swift              # App entry point, Window scenes
├── Animation/
│   └── SectionAnimationController.swift  # Section transition animations
├── Managers/
│   ├── BeaconManager.swift       # Beacon overlay for session cycling
│   ├── HotkeyManager.swift       # Global keyboard shortcuts (KeyboardShortcuts library)
│   ├── LogManager.swift          # In-app logging system
│   ├── NotificationManager.swift # macOS notifications for idle/permission states
│   ├── SessionManager.swift      # Session list, cycling logic (no persistence)
│   ├── StatusBarManager.swift    # Menu bar icon (NSStatusItem + NSPopover)
│   └── UpdateManager.swift       # Sparkle auto-updates
├── Models/
│   ├── CyclingEngine.swift       # Session cycling protocol and implementation
│   ├── HookEventMapper.swift     # Hook event → state mapping (Claude Code + OpenCode + Codex)
│   ├── Shortcut+Persistence.swift # Save/load shortcuts via UserDefaults (extends ShortcutField's Shortcut)
│   ├── QueueOrderMode.swift      # Fair, Prio, Static, Grouped modes
│   ├── Session.swift             # Session data model
│   ├── SessionState.swift        # idle, working, permission, backburner, compacting
│   ├── TerminalType.swift        # Terminal app abstraction (iTerm2, Kitty, Ghostty, WezTerm — latter two recognized but no bridge yet)
│   └── ...                       # AppConstants, AppStorageKeys, BeaconPosition/Size/Anchor, ConfigValidator, SessionStatsCalculator, SessionTitleMode
├── Services/
│   ├── HookServer.swift          # HTTP server receiving hooks (/hook, /kitty-event)
│   ├── iTerm2Bridge.swift        # Unix socket communication with Python daemon
│   ├── KittyBridge.swift         # Kitty terminal integration via kitten CLI
│   ├── TerminalBridge.swift      # Terminal abstraction protocol + TerminalActivation
│   └── TerminalBridgeRegistry.swift  # Bridge registration and lifecycle
├── Views/
│   ├── AboutView.swift           # About window
│   ├── BeaconContentView.swift   # Beacon overlay content
│   ├── IntegrationHubView.swift  # Terminal/agent integration setup
│   ├── KittySetupView.swift      # Kitty configuration wizard
│   ├── LogsSettingsView.swift    # In-app log viewer
│   ├── MenuBarView.swift         # Menu bar popover
│   ├── OnboardingView.swift      # First-run setup
│   ├── RenameSessionView.swift   # Session rename sheet
│   ├── SessionMonitorView.swift  # Main window session list
│   ├── SessionRowView.swift      # Individual session row
│   ├── SettingsView.swift        # Preferences window
│   └── ...                       # BeaconSettingsView, SessionListController, SettingWithDescription
└── Resources/
    ├── iterm2_daemon.py          # Python daemon for iTerm2 API
    ├── juggler_watcher.py        # Kitty event watcher
    ├── install_kitty_watcher.sh  # Kitty watcher install script
    ├── hooks/
    │   ├── install.sh            # Hook installation script
    │   ├── notify.sh             # Hook notification script
    │   └── uninstall.sh          # Integration cleanup (single source of truth)
    ├── codex-hooks/
    │   └── codex-notify.sh       # Codex hook notification script
    └── opencode-plugin/
        └── juggler-opencode.txt  # OpenCode plugin (bundled as .txt; installer writes it to disk as .ts)
```

**Session states:** `idle`, `permission`, `working`, `backburner` (excluded from cycle), `compacting`

**Menu bar app quirks:**
- Uses `NSStatusItem` + `NSPopover` managed by `StatusBarManager` (not SwiftUI MenuBarExtra)
- `OnboardingView` window triggers first-run setup
- `NSApp.setActivationPolicy(.regular)` shows dock icon; `.accessory` hides it

## Hook Installation

Hooks are installed to `~/.claude/hooks/juggler/`. The `notify.sh` script reads session data from stdin (JSON) and posts to Juggler's HTTP server.

Codex hooks install the bundled `codex-notify.sh` to `~/.codex/hooks/juggler/notify.sh`, register it in `~/.codex/hooks.json`, and trust it via `~/.codex/config.toml`. See [docs/tech/codex-hooks.md](docs/tech/codex-hooks.md).

## Code Style

- SwiftLint and SwiftFormat configured
- 4-space indentation, 120 char max width
- Use @Observable (not ObservableObject) for state
- Use @AppStorage for UserDefaults persistence

## Related Documentation

- [README.md](README.md) - User-facing documentation
- [docs/tech/overview.md](docs/tech/overview.md) - Technical architecture
- [docs/prd/overview.md](docs/prd/overview.md) - Product requirements document

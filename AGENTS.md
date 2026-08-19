# Repository Guidelines

This is the single source of truth for agent/contributor guidance in this repo. `CLAUDE.md` imports this file, so every coding agent shares it.

Juggler is a SwiftUI menu bar app (macOS 14+) that tracks Claude Code, OpenCode, Codex, Pi, and Antigravity sessions via hooks and provides global hotkeys to navigate between them.

## Project Structure & Module Organization

`Juggler/` contains the macOS app source. Key folders are `Models/`, `Managers/`, `Services/`, `Views/`, `Animation/`, and `Resources/` for bundled scripts such as hooks and terminal helpers. UI assets live in `Juggler/Assets.xcassets/`. Unit tests are in `JugglerTests/`. Product, technical, and planning docs live under `docs/`. Build output is written to `build/` and should not be committed. The Xcode project uses `PBXFileSystemSynchronizedRootGroup`: files added under `Juggler/` are auto-discovered — no `project.pbxproj` edits needed when adding files.

## Build, Test, and Development Commands

Use `just` targets for routine work:

```bash
just build        # Build the Juggler Debug scheme into build/
just resolve-deps # Resolve/fetch Swift package dependencies without building
just run          # Build and run (usually the user does this, not the agent)
just test         # Run unit tests only (fast, no UI)
just clean        # Remove the build directory
just lint         # Run SwiftLint (--strict)
just format       # Run SwiftFormat
just unused-check # Check for unused code (Periphery)
just coverage     # Run unit tests and print the coverage summary
just reset-all    # Clear all app preferences/permissions/integrations (fresh-state testing)
just setup        # Install the repo's lefthook Git hooks
```

Or use Xcode: `⌘B` to build, `⌘R` to run.

**Testing workflow:** Don't run `just run` - the user runs and tests the app themselves. Just run `just build` and tell the user when it's ready for testing.

## Architecture

**Data flow:**
1. Claude Code / OpenCode / Codex / Pi / Antigravity hooks → HTTP POST to `HookServer` (port 7483)
2. `HookServer` → updates `SessionManager` (in-memory `@Observable`)
3. Global hotkeys → `ShortcutCenter` (ShortcutKitGlobal) → `HotkeyManager` → `SessionManager`
4. Activation → `TerminalBridge` (iTerm2Bridge/KittyBridge/WezTermBridge) → terminal

**Bridges & session identity:**
- `TerminalBridgeRegistry` is an `actor` singleton (`.shared`) mapping `TerminalType → any TerminalBridge`; `JugglerApp` registers the bridges and starts each one based on its `@AppStorage` key.
- `Session` has a composite identity: `terminalSessionID` plus optional `tmuxPane`.

**Project structure:**
```
Juggler/
├── JugglerApp.swift              # App entry point, Window scenes
├── Animation/
│   └── SectionAnimationController.swift  # Section transition animations
├── Managers/
│   ├── BeaconManager.swift       # Beacon overlay for session cycling
│   ├── HotkeyManager.swift       # Dispatches global shortcut actions and automatic transitions
│   ├── ShortcutCenter.swift      # ShortcutKit registry, contexts, and global activation
│   ├── LogManager.swift          # In-app logging system
│   ├── NotificationManager.swift # macOS notifications for idle/permission states
│   ├── SessionManager.swift      # Session list, cycling logic (no persistence)
│   ├── StatusBarManager.swift    # Menu bar icon (NSStatusItem + NSPopover)
│   └── UpdateManager.swift       # Sparkle auto-updates
├── Models/
│   ├── CyclingEngine.swift       # Session cycling protocol and implementation
│   ├── HookEventMapper.swift     # Hook event → state mapping (Claude Code + OpenCode + Codex + Pi + Antigravity)
│   ├── ShortcutActions.swift     # Global and session-list ShortcutKit action definitions
│   ├── QueueOrderMode.swift      # Fair, Prio, Static, Grouped modes
│   ├── Session.swift             # Session data model
│   ├── SessionState.swift        # idle, working, permission, backburner, compacting
│   ├── TerminalType.swift        # Terminal app abstraction (iTerm2, Kitty, WezTerm, Ghostty - Ghostty recognized but no bridge yet)
│   └── ...                       # AppConstants, AppStorageKeys, BeaconPosition/PositionCalculator/Size/Anchor, ConfigValidator, DailyStatsStore, SessionStatsCalculator, SessionTitleMode, StatsBarLayout
├── Services/
│   ├── HookServer.swift          # HTTP server receiving hooks (/hook, /kitty-event)
│   ├── iTerm2Bridge.swift        # Unix socket communication with Python daemon
│   ├── KittyBridge.swift         # Kitty terminal integration via kitten CLI
│   ├── WezTermBridge.swift       # WezTerm integration via wezterm cli (activation + gone-cleanup only)
│   ├── TerminalBridge.swift      # Terminal abstraction protocol + TerminalActivation
│   ├── TerminalBridgeRegistry.swift  # Bridge registration and lifecycle
│   └── ...                       # CodexHooksInstaller, AntigravityHooksInstaller, OpenCodePluginInstaller, PiExtensionInstaller, ScriptInstaller, ConfigFileWriter (agent integration installers)
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
│   └── ...                       # BeaconSettingsView, SessionListController, SettingWithDescription, CodexSetupController, AntigravitySetupController, BusyStatsCorner, StatsChartView, WindowAccessor
└── Resources/
    ├── iterm2_daemon.py          # Python daemon for iTerm2 API
    ├── juggler_watcher.py        # Kitty event watcher
    ├── install_kitty_watcher.sh  # Kitty watcher install script
    ├── hooks/
    │   ├── install.sh            # Hook installation script
    │   ├── notify.sh             # Hook notification script
    │   └── uninstall.sh          # Integration cleanup (single source of truth)
    ├── codex-hooks/
    │   ├── codex-install.sh      # Codex hook install script
    │   └── codex-notify.sh       # Codex hook notification script
    ├── antigravity-hooks/
    │   └── antigravity-notify.sh # Antigravity hook notification script
    ├── opencode-plugin/
    │   └── juggler-opencode.txt  # OpenCode plugin (bundled as .txt; installer writes it to disk as .ts)
    └── pi-extension/
        └── juggler-pi.txt        # Pi extension (bundled as .txt; installer writes it to disk as .ts)
```

**Session states:** `idle`, `permission`, `working`, `backburner` (excluded from cycle), `compacting`

**Menu bar app quirks:**
- Uses `NSStatusItem` + `NSPopover` managed by `StatusBarManager` (not SwiftUI MenuBarExtra)
- `OnboardingView` window triggers first-run setup
- `NSApp.setActivationPolicy(.regular)` shows dock icon; `.accessory` hides it

**Recurring trap (full post-mortems in `docs/log/`):** iTerm2 session IDs are prefixed
`w1t0p0:UUID`, but iTerm2's FocusMonitor sends the bare `UUID`. Match with `hasSuffix`, never
`==` - exact matching has broken focus-sync and terminal-info more than once.

## Hook Installation

Hooks are installed to `~/.claude/hooks/juggler/`. The `notify.sh` script reads session data from stdin (JSON) and posts to Juggler's HTTP server. `notify.sh` detects the terminal type from env vars (`$KITTY_WINDOW_ID` → Kitty, else `$ITERM_SESSION_ID` → iTerm2).

Codex hooks install the bundled `codex-notify.sh` to `~/.codex/hooks/juggler/notify.sh`, register it in `~/.codex/hooks.json`, and trust it via `~/.codex/config.toml`. See [docs/tech/codex-hooks.md](docs/tech/codex-hooks.md).

Pi installs the bundled `juggler-pi.txt` as a TypeScript extension to `~/.pi/agent/extensions/juggler-pi.ts` (honoring `PI_CODING_AGENT_DIR`). No trust step or feature flag — Pi auto-discovers global extensions on restart/`/reload`. See [docs/tech/pi-extension.md](docs/tech/pi-extension.md).

Antigravity installs the bundled `antigravity-notify.sh` to `~/.gemini/hooks/juggler/notify.sh` and registers it under a `"juggler"` key in `~/.gemini/config/hooks.json`. No trust step or feature flag. Only `PreInvocation` (working) and `Stop` (idle) are registered; `Stop` requires the hook to return a `decision`, so the script always emits an allow. No permission/compaction/session-end events. See [docs/tech/antigravity-hooks.md](docs/tech/antigravity-hooks.md).

### Testing Hooks

Test the hook server manually:
```bash
curl -X POST "http://localhost:7483/hook" \
  -H "Content-Type: application/json" \
  -d '{"agent":"claude-code","event":"SessionStart","terminal":{"sessionId":"test123","cwd":"/tmp"},"hookInput":{"session_id":"abc123"}}'
```

## Coding Style & Naming Conventions

This is a Swift codebase (Xcode `SWIFT_VERSION = 5.0` language mode) with 4-space indentation and a 120-character line target. Formatting is enforced by `.swiftformat`; linting is enforced by `.swiftlint.yml`. Follow existing Swift naming: `UpperCamelCase` for types, `lowerCamelCase` for properties/functions, and test files named after the subject, for example `SessionManagerTests.swift`. Use `@Observable` (not `ObservableObject`) for app state and keep persistence in `@AppStorage` where applicable.

- Tests use the Swift Testing framework (`@Test`, `#expect`), not XCTest.
- `Decodable` payload structs declare an explicit `nonisolated init(from:)` to avoid Swift 6 actor-isolation warnings.
- Don't add explanatory "why this case exists" comments next to new switch cases, hook entries, set members, or tests — even when a one-off example exists nearby. The codebase deliberately omits them; let symbol names speak and push rationale into `docs/tech/*.md` or the commit/PR body.
- Adding a `LogManager` category means adding the enum case, its debug flag, and handling it in `shouldPrint`.
- **Setup/integration UIs:** in onboarding/integration screens (e.g. `IntegrationHubView`), give each discrete action its own button and status indicator — don't bundle multiple side-effecting actions behind one button. If an action bypasses another tool's safeguard (e.g. "Enable in Codex" skips Codex's own hook-review), surface that in a caption and offer the manual alternative.

## Testing Guidelines

Add unit tests in `JugglerTests/` for business logic and service behavior. Keep tests narrowly scoped and name methods for the behavior under test. Run `just test` before pushing. `JugglerTests` must run with `-parallel-testing-enabled NO` (the `test` and `coverage` recipes already do): tests share process-global state (`UserDefaults.standard`, `SessionManager.shared`, `TerminalBridgeRegistry.shared`), and Swift Testing's `.serialized` only serializes within one process — it can't stop interference between xcodebuild's parallel runner processes.

Always ask the user for explicit approval before running any test that launches Juggler, including `just test-idle-cpu` and any UI tests added in the future. App-launching tests can interfere with the user's running Juggler instance and take over screen focus.

## Documentation

Project docs live in `docs/` (start at [docs/overview.md](docs/overview.md)). After completing a feature, run `doc --update` to keep them current.

Related documentation:
- [README.md](README.md): User-facing documentation
- [docs/tech/overview.md](docs/tech/overview.md): Technical architecture
- [docs/features/overview.md](docs/features/overview.md): What each feature does

## Commit & Pull Request Guidelines

Recent history uses short Conventional Commit-style subjects such as `fix: show shortcuts in lowercase` and `chore: improve docs`. Keep commit titles imperative and concise. Before pushing, expect `lefthook` to run formatters, lint, `just build-strict`, `just test`, and `just unused-check`. PRs should include a clear summary, linked issue or plan doc when relevant, and screenshots or recordings for visible UI changes.

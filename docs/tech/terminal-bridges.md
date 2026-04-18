# Terminal Bridges

Terminal bridges abstract terminal-specific APIs behind a uniform protocol so that session activation, highlighting, and info lookup work identically across iTerm2, Kitty, and (eventually) other terminals.

## Protocol

```swift
protocol TerminalBridge: Sendable {
    func start() async throws
    func stop() async
    func activate(sessionID: String) async throws
    func highlight(sessionID: String,
                   tabConfig: HighlightConfig?,
                   paneConfig: HighlightConfig?) async throws
    func getSessionInfo(sessionID: String) async throws -> TerminalSessionInfo?
}
```

(`Services/TerminalBridge.swift:9-15`)

| Method | Purpose |
|--------|---------|
| `start` | Boot any background daemon or socket connection |
| `stop` | Tear down, release resources |
| `activate` | Bring the given session to the foreground |
| `highlight` | Flash tab/pane with an RGB color for N seconds |
| `getSessionInfo` | Return `TerminalSessionInfo` (tab name, window name, indices) |

## TerminalActivation

A static orchestrator (`TerminalBridge.swift:39-157`) that drives activation end-to-end:

1. Look up the bridge for the session's `TerminalType` via `TerminalBridgeRegistry`.
2. Call `bridge.activate(sessionID:)`.
3. If the session is tmux-backed, select the tmux pane.
4. Trigger `highlight()` based on `ActivationTrigger` (`.hotkey`, `.guiSelect`, `.notification`) and user highlight preferences.
5. On `.sessionNotFound` from the bridge, remove the stale session from `SessionManager`.

## Registry

```swift
actor TerminalBridgeRegistry {
    static let shared = TerminalBridgeRegistry()

    func register(_ bridge: any TerminalBridge, for type: TerminalType)
    func bridge(for type: TerminalType) -> (any TerminalBridge)?
    func start(_ type: TerminalType) async throws
    func stopAll() async
}
```

(`Services/TerminalBridgeRegistry.swift:8-45`)

The registry is an actor singleton. At app launch, bridges are instantiated and registered; the app then calls `start(type)` for the user-configured terminal. On exit or preference change, `stopAll()` halts all bridges.

## Supported Terminals

`Models/TerminalType.swift` defines:

| Case | Bridge |
|------|--------|
| `.iterm2` | `iTerm2Bridge` |
| `.kitty` | `KittyBridge` |
| `.ghostty` | None — recognized for detection only |
| `.wezterm` | None — recognized for detection only |

Each case carries a `bundleIdentifier` and `iconName` for app discovery and UI display.

## Adding a New Bridge

1. Create `FooBridge.swift` as `actor FooBridge: TerminalBridge`.
2. Implement the five protocol methods. Reference `KittyBridge` for CLI-driven terminals or `iTerm2Bridge` for socket-daemon terminals.
3. Add the `TerminalType` case (`.foo`) with `bundleIdentifier` and `iconName`.
4. Register at app init: `await TerminalBridgeRegistry.shared.register(FooBridge.shared, for: .foo)`.
5. For inbound events (focus changes, session close), either plug into the existing `/hook` pipeline via a shell script or add a new endpoint in `HookServer`.

## Concurrency

All bridges are actors. Callers `await` every method. Internal state — daemon processes, socket paths, active reset tasks — is actor-isolated. External daemon callbacks must dispatch back into the actor context.

## Lifecycle

- **Launch** — the app instantiates both bridges, registers them, and calls `start()` on the active one.
- **Preference change** — `stopAll()` then `start()` for the new type.
- **Exit** — `stopAll()`.

Session restoration happens in `SessionManager`, independent of bridge lifecycle.

## Gotchas

- **Timeouts** — `iTerm2Bridge` sets `activateTimeout = 2.0 s` and `highlightTimeout = 1.0 s`. Bridge methods must respect these.
- **Sendable** — bridges must be `Sendable` so they cross actor boundaries safely.
- **`sessionNotFound` vs `connectionFailed`** — use `.sessionNotFound` only when the terminal confirms the session is gone, so `TerminalActivation` can clean up state. Transient errors should be `.connectionFailed`.
- **Highlight reset** — bridges that flash colors must track and cancel the reset task if a new highlight arrives before the first expires. See `KittyBridge`'s `activeTabResetTasks`.

---

[← Back to Tech Overview](overview.md)

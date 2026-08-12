# Session Management

The SessionManager is the central state manager for tracking agent sessions (Claude Code, OpenCode, Codex, Pi, Antigravity).

## Implementation

**File:** `Managers/SessionManager.swift`

- `@Observable` singleton
- In-memory session storage
- Cycling logic via CyclingEngine
- State transitions with animations

## Session Model

```swift
struct Session: Identifiable, Codable, Equatable {
    var claudeSessionID: String      // Agent session ID; refreshed when a new thread takes the pane
    let terminalSessionID: String    // e.g., "w0t0p0:UUID"
    var tmuxPane: String?            // e.g., "%1", nil if not inside tmux
    var id: String { ... }           // Computed: "\(terminalSessionID):\(tmuxPane)" or terminalSessionID
    let terminalType: TerminalType   // .iterm2, .kitty, .wezterm
    let agent: String                // "claude-code", "opencode", or "codex"
    let projectPath: String          // Working directory
    var terminalTabName: String?     // Tab name from terminal
    var terminalWindowName: String?  // Window name
    var tmuxSessionName: String?     // tmux session name
    var customName: String?          // User-assigned name
    var state: SessionState          // Current state
    var startedAt: Date              // Session start time
    var lastBecameIdle: Date?        // Queue-ordering sort key for Fair/Prio
    var lastBecameWorking: Date?     // Start of the current busy turn
    var busyTimeToday: TimeInterval  // Working time accrued today (reset at midnight)
    var paneIndex: Int               // Pane position (for splits)
    var paneCount: Int               // Total panes in tab
    var gitBranch: String?           // Current git branch
    var gitRepoName: String?         // Repository name
    var transcriptPath: String?      // Path to transcript JSONL
    var remoteHost: String?          // SSH host, nil for local sessions
}
```

## Session States

```swift
enum SessionState: String, Codable {
    case working     // Claude is processing
    case idle        // Waiting for user input
    case permission  // Waiting for permission
    case backburner  // Manually deprioritized
    case compacting  // Context compaction

    var isIncludedInCycle: Bool {
        self == .idle || self == .permission
    }
}
```

## Data Flow

### Session Registration

1. Hook fires (e.g., `SessionStart`)
2. `notify.sh` enriches with terminal info
3. HTTP POST to HookServer
4. `addOrUpdateSession()` creates/updates session

### State Transitions

1. Hook event arrives
2. `HookEventMapper` maps to state
3. `addOrUpdateSession()` updates session and, on a state change, calls `applyStateChange()`
4. `applyStateChange()` orchestrates the transition:
   - Section transition animation (`SectionAnimationController`)
   - `handleStateTransition()` - queue reorder (per `QueueOrderMode`) and busy-time stats accrual
   - Auto-advance / auto-restart triggers (posts `.shouldAutoAdvance` / `.shouldAutoRestart`)

## Cycling Engine

**File:** `Models/CyclingEngine.swift`

Protocol-based design for testability:

```swift
protocol CyclingEngine {
    func cycleForward(sessions: [Session], focusedSessionID: String?, state: CyclingState) -> CyclingResult
    func cycleBackward(sessions: [Session], focusedSessionID: String?, state: CyclingState) -> CyclingResult
    func syncStateToFocus(sessions: [Session], focusedSessionID: String?, state: CyclingState) -> CyclingState
}
```

### Cycling Logic

1. Filter to cyclable sessions (idle/permission)
2. Advance index based on direction
3. Wrap around at boundaries
4. Report whether cycling moved (`didMove`) so the caller can decide whether to advance the highlight color

The rules that govern the highlight color itself live in [Session Highlight Color](highlight-color.md).

### Queue Modes

Sessions are reordered based on mode when state changes:

| Mode | Behavior |
|------|----------|
| Fair | Return-to-idle → bottom of list |
| Prio | Return-to-idle → top of list |
| Static | No reordering |
| Grouped | Static order, grouped by terminal window |

When Permission First is enabled, Fair and Prio partition their cyclable sessions into permission and idle queues.
State-driven insertions retain the selected mode's `lastBecameIdle` ordering within each queue. Enabling the
preference stable-partitions the current order, preserving manual Send to Back placement within each queue.
Static and Grouped ignore this preference.

## Hotkeys

`HotkeyManager` (`Managers/HotkeyManager.swift`) registers the global shortcuts and drives activation:

| Shortcut (default) | Action |
|---|---|
| `⌘⇧K` / `⌘⇧J` | Cycle forward / backward through cyclable sessions |
| `⌘⇧L` | Backburner the current session |
| `⌘⇧H` | Reactivate all backburnered sessions |
| `⌘⇧;` | Show monitor (popover → main window → dismiss cycle) |
| `⌘⇧E` | Jump to the session from the most recent delivered notification |

The jump-to-latest shortcut activates `SessionManager.lastNotifiedSessionID` (recorded by `NotificationManager` via `recordLastNotification`), independent of cycle order, and shows "No Notification" in the beacon if there's no recorded session or it's gone.

Every activation surface delegates to `SessionActivator`. It processes activation requests in request order, holds the `beginActivation` / `endActivation` guard for each full terminal operation, and returns a typed outcome. Cycling-style workflows use `activateFirstAvailable`, which silently skips stale sessions until a live target activates or no candidate remains.

## Reorder Animations

**File:** `Animation/SectionAnimationController.swift`

Handles visual transitions when sessions change sections:

### UP Animation (busy → idle)

Smooth vertical movement via `matchedGeometryEffect` (0.4s)

### DOWN Animation (idle → busy)

1. Slides right and fades out (0.3s)
2. Off-screen delay (1.2s)
3. Slides in from right (0.3s)

## Backburner Handling

Special logic to preserve backburner state:

In `addOrUpdateSession()` (`SessionManager.swift:605`), when the existing state is `.backburner` and the event isn't `UserPromptSubmit`, the method calls `mergeSessionMetadata(...)` to refresh tmux/git/transcript fields and returns without changing state - preserving backburner.

Only `UserPromptSubmit` or explicit reactivation (via `updateSessionState`, not this method) exits backburner.

## Stale Session Cleanup

Sessions are removed reactively (no polling timer):

1. iTerm2 daemon and Kitty watcher push `session_terminated` events when tabs close, routed through `SessionManager.removeSessionsByTerminalID`.
2. Activation that fails because the session is gone (`TerminalActivation.activate` detecting a missing session) calls `removeSession` and throws `.sessionNotFound`. `SessionActivator.activateFirstAvailable` maps that to an unavailable target and asks its candidate provider for the next session until a live session activates or none remain. This backstops Kitty in particular: its watcher delivers `session_terminated` over fire-and-forget HTTP with no retry, so a dropped event would otherwise leak the session until the next activation attempt prunes it.

---

[← Back to Tech Overview](overview.md)

# Session Management

The SessionManager is the central state manager for tracking Claude Code sessions.

## Implementation

**File:** `Managers/SessionManager.swift`

- `@Observable` singleton
- In-memory session storage
- Cycling logic via CyclingEngine
- State transitions with animations

## Session Model

```swift
struct Session: Identifiable, Codable, Equatable {
    let claudeSessionID: String      // Claude session ID (may be shared across tmux panes)
    let terminalSessionID: String    // e.g., "w0t0p0:UUID"
    var tmuxPane: String?            // e.g., "%1", nil if not inside tmux
    var id: String { ... }           // Computed: "\(terminalSessionID):\(tmuxPane)" or terminalSessionID
    let terminalType: TerminalType   // .iterm2, .kitty
    let agent: String                // "claude-code" or "opencode"
    let projectPath: String          // Working directory
    var terminalTabName: String?     // Tab name from terminal
    var terminalWindowName: String?  // Window name
    var tmuxSessionName: String?     // tmux session name
    var customName: String?          // User-assigned name
    var state: SessionState          // Current state
    var startedAt: Date              // Session start time
    var lastBecameIdle: Date?        // For idle time tracking
    var accumulatedIdleTime: TimeInterval
    var lastBecameWorking: Date?     // For working time tracking
    var accumulatedWorkingTime: TimeInterval
    var paneIndex: Int               // Pane position (for splits)
    var paneCount: Int               // Total panes in tab
    var gitBranch: String?           // Current git branch
    var gitRepoName: String?         // Repository name
    var transcriptPath: String?      // Path to transcript JSONL
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
3. `addOrUpdateSession()` updates session
4. `handleStateTransition()` triggers:
   - Reorder animation
   - Notification (if enabled)
   - Stats tracking

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
4. Track highlight color index

### Queue Modes

Sessions are reordered based on mode when state changes:

| Mode | Behavior |
|------|----------|
| Fair | Return-to-idle → bottom of list |
| Prio | Return-to-idle → top of list |
| Static | No reordering |
| Grouped | Static order, grouped by terminal window |

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

```swift
// In addOrUpdateSession()
if oldState == .backburner && event != "UserPromptSubmit" {
    // Update metadata but preserve backburner
    return
}
```

Only `UserPromptSubmit` or explicit reactivation exits backburner.

## Stale Session Cleanup

Sessions are removed reactively (no polling timer):

1. iTerm2 daemon pushes `session_terminated` events when tabs close
2. Activation failure detection removes sessions not found in the terminal
3. Kitty sessions are cleaned up on activation failure (no persistent daemon connection)

---

[← Back to Tech Overview](overview.md)

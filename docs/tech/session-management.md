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
    let claudeSessionID: String      // Claude's session ID
    let terminalSessionID: String    // iTerm2 pane UUID (e.g., "w0t0p0:UUID")
    let terminalType: TerminalType   // .iterm2 (future: .kitty, etc.)
    let projectPath: String          // Working directory
    var terminalTabName: String?     // Tab name from iTerm2
    var terminalWindowName: String?  // Window name
    var customName: String?          // User-assigned name
    var state: SessionState          // Current state
    var lastUpdated: Date            // Last state change
    var startedAt: Date              // Session start time
    var paneIndex: Int               // Pane position (for splits)
    var paneCount: Int               // Total panes in tab
    var gitBranch: String?           // Current git branch
    var gitRepoName: String?         // Repository name
    var transcriptPath: String?      // Path to transcript JSONL
    var lastUserMessage: String?     // Most recent user prompt
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
    func cycleForward(sessions: [Session], state: CyclingState) -> CyclingState
    func cycleBackward(sessions: [Session], state: CyclingState) -> CyclingState
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

## Reorder Animations

**File:** `Animation/ReorderAnimator.swift`

Handles visual transitions when sessions change sections:

### UP Animation (busy → idle)

1. Session starts at current position
2. Slides up to new position (0.6s)
3. Fades to full opacity (0.2s)

### DOWN Animation (idle → busy)

1. Slides right and fades out (0.4s)
2. Moves to new section (invisible)
3. Slides in from right (0.4s)

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

Background sync removes sessions no longer in iTerm2:

1. Timer fires every 5 seconds
2. Query daemon for active terminal sessions
3. Remove sessions not found in iTerm2
4. Also triggered on activation failure

---

[← Back to Tech Overview](overview.md)

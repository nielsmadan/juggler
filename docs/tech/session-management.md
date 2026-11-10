# Session Management

The SessionManager is the central state manager for tracking agent sessions (Claude Code, OpenCode, Codex, Pi, Antigravity).

- [Implementation](#implementation)
- [Session model](#session-model)
- [Session notes](#session-notes)
- [Conversation dispositions](#conversation-dispositions)
- [Session states](#session-states)
- [Data flow](#data-flow)
- [Cycling engine](#cycling-engine)
- [Hotkeys](#hotkeys)
- [Activation and notifications](#activation-and-notifications)
- [Reorder animations](#reorder-animations)
- [Backburner handling](#backburner-handling)
- [Stale session cleanup](#stale-session-cleanup)

## Implementation

**File:** `Managers/SessionManager.swift`

- `@Observable` singleton
- In-memory session storage
- Durable conversation notes and hidden/backburner dispositions in separate stores
- Cycling logic via CyclingEngine
- State transitions with animations

## Session Model

```swift
struct Session: Identifiable, Codable, Equatable {
    var agentSessionID: String      // Agent session ID; refreshed when a new thread takes the pane
    let terminalSessionID: String    // e.g., "w0t0p0:UUID"
    var tmuxPane: String?            // e.g., "%1", nil if not inside tmux
    var id: String { ... }           // Computed: "\(terminalSessionID):\(tmuxPane)" or terminalSessionID
    let terminalType: TerminalType   // .iterm2, .kitty, .wezterm
    var agent: String                // "claude-code", "opencode", "codex", "pi", or "antigravity"
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
    var note: String?                // User-assigned note for this agent conversation
}
```

## Session Notes

Notes are durable per agent conversation, not per terminal row. `SessionNoteStore` keys each note by the pair
`(agent, agentSessionID)`, so resuming the same conversation restores its note even when it appears in another pane.
All live rows for that pair stay synchronized. When a different `agentSessionID` takes over an existing pane, the row
loads that conversation's own stored note (or no note) instead of inheriting the previous conversation's note.

Conversation ownership changes only on agent-specific start or prompt events. Later lifecycle events from a previous
conversation are ignored instead of replacing the pane's current identity or state. Removal events compare the agent
namespace and, when supplied, the agent session ID before deleting the row.

The store decodes the complete `UserDefaults` collection once at initialization and serves subsequent reads from an
in-memory dictionary. Each note change or clear synchronously rewrites the complete collection, sorted by agent and
agent session ID for deterministic encoding.

A session without an agent session ID cannot form a durable key, so its note remains transient on the live `Session`.
If the row later receives an ID, that transient note is saved under the resulting key. Removing a live row does not
remove its persisted note, which allows a later resume of the same conversation to recover it.

Notes and conversation dispositions are restored from disk. The live session list remains in memory and is rebuilt
from hook and terminal events after every app launch.

## Conversation Dispositions

`SessionDispositionStore` persists Hide, Prio and backburner intent under `(agent, agentSessionID)`, independently of
`SessionNoteStore` and `HiddenBindingStore`. `SessionManager.shared` injects a UserDefaults-backed store;
ordinary `SessionManager()` instances use an in-memory disposition store. A row's terminal/pane ID identifies
its live location, while its conversation identity owns durable intent. Duplicate live rows synchronize every
disposition field, with one persistence update and automation effects only for the initiating row. A new
conversation in the same pane loads its own disposition, never the old conversation's.

Until a stable nonempty conversation identity arrives, choices remain on the live row. Per-field transient
overrides distinguish explicit Unhide/Reactivate from untouched state. Filling the missing identity applies
those overrides over the stored disposition, persists the reconciled result and synchronizes duplicate rows.
A stable identity replacement instead loads the replacement's stored intent and clears old deferred work and
details. Stale non-establishing events cannot replace ownership.

The `sessionDispositions` UserDefaults data contains a version-1 envelope of records. Writes sort records by
agent/session ID and JSON keys for deterministic encoding. Decoding skips malformed records and invalid keys;
the last valid duplicate wins, including an empty record that clears an earlier one. Empty dispositions are
removed. Corrupt or unsupported envelopes log an error and yield an empty in-memory store.

`Session.isHidden` is orthogonal to `SessionState`: Hide changes neither state nor busy timestamps, so hooks,
metadata, turn durations and busy-time commits continue. `Session.isCycleEligible` combines the state-only
`SessionState.isIncludedInCycle` with `!isHidden`; keep the state-only predicate where the prior state is
needed, such as Antigravity backburner wake logic.

`SessionManager.listedSessions` applies the launch-scoped `showsHiddenSessions` flag, initially false. Both
views, their selection/navigation, empty states and name disambiguation use that projection. Revealed hidden
rows retain their normal section/order. Stats intentionally read raw `sessions` instead. A focused hidden row
remains a valid focus anchor for cycling away; an unfocused hidden busy anchor is cleared, including when
transient-to-stable hydration discovers persisted Hide.

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
2. hooklinesinker enriches with terminal info (Antigravity uses Juggler's bundled notify script)
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

1. Filter to cycle-eligible sessions (non-hidden idle/permission)
2. Advance index based on direction
3. Wrap around at boundaries
4. Report whether cycling moved (`didMove`) so the caller can decide whether to advance the highlight color

The rules that govern the highlight color itself live in [Session Highlight Color](highlight-color.md).

### Queue Modes

Sessions are reordered based on mode when state changes:

| Mode | Behavior |
|------|----------|
| Fair | Return-to-idle → bottom of list; prio sessions → bottom of the prio group at the top |
| Prio | Return-to-idle → top of list |
| Static | No reordering |
| Grouped | Static order, grouped by terminal window |

When Permission First is enabled, Fair and Prio partition their cyclable sessions into permission and idle queues.
State-driven insertions retain the selected mode's `lastBecameIdle` ordering within each queue. Enabling the
preference stable-partitions the current order, preserving manual Send to Back placement within each queue.
Static and Grouped ignore this preference.

Only Fair honours the per-conversation Prio flag (`QueueOrderMode.supportsPrioritizedSessions`). A prio session
entering its waiting band uses `QueuePosition.bottomOfPrioritized(WaitingBand)`: just above the band's first plain
session, or the band's end when it has none. The band is permission or idle under Permission First, otherwise the
shared waiting band, and is resolved before `targetIndex` so the index lookup stays a pure function of the array.
`synchronizeDisposition` and the identity-update path in `addOrUpdateSession` both call
`reconcilePrioritizedPlacement` when a row's flag flips: turning prio on resets `lastBecameIdle` and moves the row
to the bottom of the prio group, which keeps a later `reorderForMode` sort (prio first, then `lastBecameIdle`) in
agreement; turning it off moves the row just below the remaining prio group, unless it already sits lower. Send to
Back ignores the flag and puts the row at the bottom of its band.

### Sending a Session Off

Send to Back and Backburner with "Go to next session on backburner" both land on
`SessionManager.nextSession(afterSendingOff:)`. In Fair and Prio that is the head of the queue — the first
cyclable session other than the one sent off — rather than the session that followed it. Following the old
position let the cursor settle mid-list: repeated Send to Back rotated only the sessions below it, so the ones at
the top (permission sessions, under Permission First) were never reached. Static and Grouped have no queue and
fall back to `currentSession`. `prepareJump(afterSendingOff:)` checks there is a target and advances the cycling
colour for both actions. Both hotkeys then resolve the target through `focusNextSession(afterSendingOff:)`, which
records it as the focused session per activation attempt, so the cursor follows the jump even for terminals that
send no focus event (WezTerm), and a stale head is skipped by the retry loop. Backburnering a busy session also
clears the `lastActiveSessionID` anchor, so later hotkeys don't keep targeting the backburnered session. The
session window's `o` key uses the same rule for its selection.

## Hotkeys

`ShortcutCenter` (`Managers/ShortcutCenter.swift`) registers global bindings through ShortcutKitGlobal and
delegates fired actions to `HotkeyManager` (`Managers/HotkeyManager.swift`), which drives activation:

| Shortcut (default) | Action |
|---|---|
| `⌘⇧K` / `⌘⇧J` | Cycle forward / backward through cyclable sessions |
| `⌘⇧L` | Backburner the current session |
| `⌘⇧O` | Send the current session to the back of its queue (Fair/Prio only) |
| `⌘⇧H` | Reactivate all backburnered sessions |
| `⌘⇧;` | Show monitor (popover → main window → dismiss cycle) |
| `⌘⇧E` | Jump to the session from the most recent delivered notification |
| `⌘⇧M` | Edit the note for the focused tracked session |

The note shortcut requires one unambiguous focus match. When multiple remote tmux sessions share the same live local
host pane and no unique session can be established, the shortcut reports that there is no active session.

The jump-to-latest shortcut resolves `SessionManager.lastNotificationTarget`, independent of cycle order, and shows
"No Notification" if it has been invalidated or its row is gone.

ShortcutKit 0.8.0 binds local dispatch handlers per activation. `keyWindowShortcutContext` mounts only for the
receiving key window. The monitor composes the shared `sessionList` context with its own `sessionMonitor`
context (`E` Hide/Unhide, `⌘E` Show Hidden, `Y` Prio, no key repeat); the popover mounts only `sessionList`.
The monitor legend merges both contexts into one "Shortcuts" group (`CombinedShortcutLegend`); Settings lists them
separately. These bindings are independent of which row actions the Settings slots show.

Capture whether a terminal is frontmost **synchronously** in `HotkeyManager.dispatch`, before any
asynchronous work starts; the answer changes as soon as activation begins.

`ShortcutAction` raw values are persistence identifiers. Renaming a case requires migrating saved
bindings.

## Activation and Notifications

Every activation surface delegates to serialized `SessionActivator`. It validates the live row and conversation
when dequeued and again immediately before the terminal bridge call. Explicit row click/Return activation can
target a listed hidden row; cycle and automatic policies require `isCycleEligible`. `activateFirstAvailable`
skips terminal targets confirmed gone until a live candidate activates or none remain. Global Backburner and
Send to Back no-op for a focused hidden row.

Auto Next/Auto Restart requests capture the source conversation, row generation and focus-context generation;
the destination also carries its generation to the final bridge check. Hide, identity replacement, source state
or focus changes permanently invalidate stale requests, even if the row is later unhidden or returns to its old
state. After a bridge completes, an automatic request may update focus only while it still owns the activation
lifetime, focus context and same live target generation. Reset, removal, replacement and newer focus decisions win.

Notification targets contain live row ID, stable conversation identity when available, an invalidatable token
and a monotonic sequence. Hook dispatch (including injected senders), default sending, delivery completion,
Last Notification recording, banner clicks, terminal-focus handoff and the Last Notification shortcut revalidate
the target. Completion order cannot replace a newer delivered target with an older one. Hidden rows never send
or resolve notification targets. Hide rotates the token and clears its Last Notification reference; Unhide does
not revive a pre-hide banner. Identity replacement rotates validity as well. A rejected old banner cannot
activate its terminal; macOS can still foreground the posting app as described in the
[platform limitation](overview.md#notification-click-activation).

## Reorder Animations

**File:** `Animation/SectionAnimationController.swift`

Handles visual transitions when sessions change sections:

Hide and identity replacement cancel pending section animations. Hidden rows receive state/reorder updates
without animation; revealed hidden rows appear in their current section without replaying stale transitions.

### UP Animation (busy → idle)

Smooth vertical movement via `matchedGeometryEffect` (0.4s)

### DOWN Animation (idle → busy)

1. Slides right and fades out (0.3s)
2. Off-screen delay (1.2s)
3. Slides in from right (0.3s)

### Section membership

Busy is `working` or `compacting` only — `permission` belongs to Idle. Treating permission as Busy
skips the reorder on permission → working and leaves the session stranded at the top of Busy.
"Bottom of Busy" means immediately before the first Backburner row, or last when there are no
Backburner rows.

### Why the animation keys off session IDs

SwiftUI does not interpolate rows moving between separate section stacks. Headers and rows render
in a single `LazyVStack` with stable row IDs, and the container animation is keyed to the ordered
session-ID array (`sessions.map(\.id)`). The row order, not the session state, is the reliable
signal for cross-section movement: animating the state change, the reorder, or
`matchedGeometryEffect` alone was not enough.

## Backburner Handling

`BackburnerDisposition` saves whether the conversation was awaiting the user, the shelving timestamp and valid
turn-count baselines by hooklinesinker binding. Backburnered rows continue merging metadata and binding observations
while retaining `.backburner`. Hide is independent: waking or explicitly reactivating does not unhide a conversation.

Live `UserPromptSubmit` (Cursor: `beforeSubmitPrompt`) wakes it. Antigravity, which has no such event, wakes on a working event only if it was
awaiting the user when shelved. Explicit Reactivate clears the persisted backburner field across duplicate rows.

Launch hydration is more conservative. The incoming `observedAt` must be strictly newer than `backburneredAt`,
and one of these must prove activity while Juggler was offline:

- An explicitly supplied nonnegative integer turn count exceeds the saved baseline for the **same binding**.
- The snapshot event is `UserPromptSubmit` (Cursor: `beforeSubmitPrompt`).
- It is a qualifying Antigravity working event and the saved awaiting-user flag is true.

Missing, malformed or negative counts, unknown bindings, unchanged counts and older/equal timestamps do not prove
a wake. A generic newer working snapshot alone is insufficient. Ambiguous snapshots remain shelved until a live
prompt, qualifying Antigravity event or explicit Reactivate. Hydration does not trigger automatic activation.

## Stale Session Cleanup

Sessions are removed reactively (no polling timer). Two manual escape hatches cover rows the
automatic paths cannot clear: **Remove**, which suppresses stale hooklinesinker bindings until activity,
and Settings → General → Reset Sessions, which clears the shared ledger and every row. `HiddenBindingStore`
belongs to Remove, not durable conversation Hide. Successful reset clears both stores' suppression/dispositions
while preserving notes and committed busy time; failure clears no local state.
See [hooks](hooks.md#hydration-at-launch) and [Reset Sessions](hooks.md#reset-sessions).

1. iTerm2 daemon and Kitty watcher push `session_terminated` events when tabs close, routed through `SessionManager.removeSessionsByTerminalID`.
2. Activation that fails because the session is gone (`TerminalActivation.activate` detecting a missing session) calls `removeSession` and throws `.sessionNotFound`. `SessionActivator.activateFirstAvailable` maps that to an unavailable target and asks its candidate provider for the next session until a live session activates or none remain. This backstops Kitty in particular: its watcher delivers `session_terminated` over fire-and-forget HTTP with no retry, so a dropped event would otherwise leak the session until the next activation attempt prunes it.

---

[← Back to Tech Overview](overview.md)

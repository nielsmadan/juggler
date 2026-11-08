# Cycle Sessions

The core feature of Juggler: cycling through agent sessions (Claude Code, OpenCode, Codex, Pi, Antigravity) using global hotkeys.

## Global Shortcuts

| Shortcut | Action |
|----------|--------|
| `⇧⌘K` | Cycle forward through sessions |
| `⇧⌘J` | Cycle backward through sessions |
| `⇧⌘L` | Backburner current session |
| `⇧⌘O` | Send current session to the back of its queue |
| `⇧⌘H` | Reactivate all backburnered sessions |
| `⇧⌘E` | Activate session from last notification |
| `⇧⌘M` | Edit note for the focused tracked session |
| `⇧⌘;` | Show session monitor window |

All shortcuts are customizable in **Settings > Shortcuts**.

## Session Notes

Press `⇧⌘M` from any app to edit the note for the uniquely focused tracked session in an active terminal. Juggler does not guess or fall back to another session: if no active terminal has exactly one focused tracked session, it shows **"No Active Session"**.

Notes use a compact single-line editor. Press `Return` to save or `Escape` to cancel. They are stored with the coding-agent conversation, so resuming the same conversation restores its note. Starting a new conversation in the same terminal pane does not inherit the old note.

If the editor is already visible and the shortcut is invoked from a different focused session, it retargets to that
session. Invoking it again for the same conversation keeps the current draft.

## Cycling Behavior

### What Gets Cycled

Only non-hidden sessions in **cyclable states** are included:
- `idle` - Waiting for user input
- `permission` - Waiting for user permission

Sessions in these states are **excluded** from cycling:
- `working` - Claude is actively working
- `compacting` - Context compaction in progress
- `backburner` - User manually deprioritized

Hidden rows are excluded in every queue mode, even when Show Hidden reveals them. Auto-advance, Auto-restart,
Send to Back and cycle-derived activation use the same exclusion. A focused hidden terminal remains tracked so
cycling can move away from it; global Backburner and Send to Back do nothing while that row is focused.
Revealed hidden rows can still be activated explicitly by click or `Return`; see [Hide and Show Hidden](main-window.md#hide-and-show-hidden).

### Cycle Order

The order of sessions depends on the **Queue Mode** setting.

### Stale Sessions

If activation lands on a session whose terminal tab/pane no longer exists, Juggler removes that session and silently advances to the next live one. Only the successful landing (or "All At Work" when none remain) is surfaced.

## Queue Modes

Juggler offers four queue ordering modes, selectable via the segmented control in the popover or main window:

### Fair

- Return-to-idle session goes to the **bottom**
- Cycling starts from the top
- Best for: Fair rotation across sessions

### Prio

- Return-to-idle session goes to the **top**
- Cycling starts from the top
- Best for: Prioritizing fresh sessions

### Static

- Sessions stay in their original order (by start time)
- No automatic reordering on state changes
- Best for: Manual organization

### Grouped

- Static order, grouped by terminal window
- Sessions from the same window appear together
- Best for: Organizing by workspace

## Sectioned Display

Sessions are grouped into sections based on state:

```
┌─────────────────────────────┐
│ Idle                        │  ← Cyclable sessions
│   ● my-feature              │
│   ● api-server              │
├─────────────────────────────┤
│ Working                     │  ← Working / compacting sessions
│   ○ data-pipeline           │
├─────────────────────────────┤
│ Backburner                  │  ← Deprioritized
│   ◐ old-project             │
└─────────────────────────────┘
```

Sectioned display applies in Fair and Prio modes; Static mode is a flat list and Grouped mode groups by terminal window.

## Backburner

Backburner allows temporarily removing a session from the cycling queue without closing it.

### Actions

- **Backburner** (`⇧⌘L`): Move current session to backburner
- **Reactivate All** (`⇧⌘H`): Move all backburnered sessions back to idle

### Behavior

- Backburnered sessions:
  - Show with `◐` icon
  - Excluded from cycling
  - Don't trigger notifications
  - Can still be clicked to activate
- When backburnering a working session:
  - Session moves to backburner section
  - Stays backburnered even when Claude finishes (hooks don't override)
  - A prompt submission or explicit reactivation exits backburner; Antigravity can also wake on a working event when it was awaiting the user when shelved
- Backburner follows the conversation across relaunches and duplicate rows. Launch hydration wakes it only with
  newer evidence of user activity; ambiguous snapshots stay shelved. See [backburner handling](../tech/session-management.md#backburner-handling).
- Hide and backburner are independent: reactivating a hidden conversation does not unhide it.

### Use Cases

- Deprioritize sessions you'll return to later
- Focus on a subset of active sessions
- Shelve sessions that are waiting but not urgent

## Terminal Highlighting

When cycling to a session, Juggler can highlight the terminal tab/pane (iTerm2 and Kitty) to make it easy to find (WezTerm sessions activate normally but aren't highlighted — WezTerm exposes no external tab/pane coloring):

### Tab Bar Highlighting

- Flash the tab with a color
- Configurable duration (1, 2, 3, or 5 seconds)
- Optional: Use cycling colors - see [Highlight Color](highlight-color.md) for the full rule set.

### Pane Background Highlighting

- Flash the pane background with a color
- Useful for split pane layouts
- Independent enable and duration; shares the single "Use cycling colors" toggle with tab highlighting

A single "Use cycling colors" toggle governs both tab and pane; highlighting can also be enabled/disabled per trigger (hotkey cycling, session select, notification click). Settings in **Settings > Highlighting**.

## Go to Next on Backburner

When enabled (default), backburnering automatically cycles to the next idle session. This allows rapid triage: backburner current, immediately see next.

Setting in **Settings > General > Backburner**.

## Permission First, Auto-Advance, and Auto-Restart

Three control-bar toggles (also bindable as Session List shortcuts) change cycling behavior:

- **Permission First**: in Fair and Prio modes, keep permission sessions ahead of idle sessions while preserving the selected queue order within each group.
- **Auto-advance**: when the current session goes busy, cycle to the next idle session.
- **Auto-restart**: when all sessions are busy and one becomes idle, jump to it.

---

[← Back to Overview](overview.md)

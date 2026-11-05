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
| `⇧⌘M` | Session menu for the focused tracked session |
| `⇧⌘;` | Show session monitor window |

All shortcuts are customizable in **Settings > Shortcuts**.

## Session Menu

Press `⇧⌘M` from any app to open the session menu for the uniquely focused tracked session in an active terminal.
Juggler does not guess or fall back to another session: if no active terminal has exactly one focused tracked
session, it shows **"No Active Session"**.

The menu appears over the centre of the frontmost window, styled like the beacon. It shows the session's name, agent,
state, prio and hidden markers, note, and the details the monitor's row slots can show (folder, branch, titles, model,
effort, permission mode, current tool, last problem, subagents, context, turns, run time). Juggler stays in the
background, so the terminal keeps focus once the menu closes.

| Action | Default key | Effect |
|--------|-------------|--------|
| Prio | `Y` | Toggles prio and closes. Fair mode only; disabled in the other modes. |
| Hide | `E` | Toggles hidden and closes. |
| Rename | `R` | Opens a name field; `Return` saves, **Clear** removes the custom name. |
| Note | `M` | Opens a note field; `Return` saves. |

The keys are the Session List and Session Monitor shortcuts, so rebinding them in **Settings > Shortcuts** changes
the menu too. Other monitor shortcuts do nothing while the menu is open. One change closes the menu. `Escape` steps
back from a name or note field to the menu and closes the menu itself; `Control-C` or clicking elsewhere closes it
from anywhere. Command shortcuts such as `⌘Q` are ignored while it is open, apart from cut, copy, paste, select all,
undo and redo in a field.

Notes are stored with the coding-agent conversation, so resuming the same conversation restores its note. Starting a
new conversation in the same terminal pane does not inherit the old note. If a new conversation takes over the pane
while the menu is open, a note still saves to the conversation the menu was opened for; the other actions report
**"Session No Longer Available"**.

Pressing the shortcut again for the same conversation closes the menu; pressing it from a different focused session
retargets the menu to that session.

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

When focus isn't on a tracked session, for example after you quit the session you were in, cycling forward starts at the first cyclable session and cycling backward starts at the last.

### Stale Sessions

If activation lands on a session whose terminal tab/pane no longer exists, Juggler removes that session and silently advances to the next live one. Only the successful landing (or "All At Work" when none remain) is surfaced.

## Queue Modes

Juggler offers four queue ordering modes, selectable via the segmented control in the popover or main window:

### Fair

- Return-to-idle session goes to the **bottom**
- Prio sessions (`Y` in the Session Monitor) instead go to the bottom of a prio group at the **top**, oldest first; see [Prio sessions](main-window.md#prio-sessions)
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

## Send to Back

`⇧⌘O` (or `o` in the session window) moves the current session to the bottom of its queue and jumps to the top of the queue: the longest-waiting session in Fair, the freshest in Prio, and permission prompts first when Permission First is on (oldest first in Fair, newest first in Prio). Working from the top therefore steps through the queue in order, and sending off a session you picked from the middle takes you back to the top instead of further down. A prio session sent back stays at the back of its band until it next goes idle. Available in Fair and Prio only.

## Go to Next on Backburner

When enabled (default), backburnering jumps to the next waiting session. In Fair and Prio that is the top of the queue, as with Send to Back; in Static and Grouped it is the next session in list order. This allows rapid triage: backburner current, immediately see next.

Setting in **Settings > General > Backburner**.

## Permission First, Auto-Advance, and Auto-Restart

Three control-bar toggles (also bindable as Session List shortcuts) change cycling behavior:

- **Permission First**: in Fair and Prio modes, keep permission sessions ahead of idle sessions while preserving the selected queue order within each group.
- **Auto-advance**: when the current session goes busy, cycle to the next idle session.
- **Auto-restart**: when all sessions are busy and one becomes idle, jump to it.

---

[← Back to Overview](overview.md)

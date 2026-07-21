# Cycle Sessions

The core feature of Juggler: cycling through agent sessions (Claude Code, OpenCode, Codex, Pi) using global hotkeys.

## Global Shortcuts

| Shortcut | Action |
|----------|--------|
| `⇧⌘K` | Cycle forward through sessions |
| `⇧⌘J` | Cycle backward through sessions |
| `⇧⌘L` | Backburner current session |
| `⇧⌘H` | Reactivate all backburnered sessions |
| `⇧⌘E` | Activate session from last notification |
| `⇧⌘;` | Show session monitor window |

All shortcuts are customizable in **Settings > Shortcuts**.

## Cycling Behavior

### What Gets Cycled

Only sessions in **cyclable states** are included:
- `idle` - Waiting for user input
- `permission` - Waiting for user permission

Sessions in these states are **excluded** from cycling:
- `working` - Claude is actively working
- `compacting` - Context compaction in progress
- `backburner` - User manually deprioritized

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
  - Only `UserPromptSubmit` or explicit reactivation exits backburner

### Use Cases

- Deprioritize sessions you'll return to later
- Focus on a subset of active sessions
- Hide sessions that are waiting but not urgent

## Terminal Highlighting

When cycling to a session, Juggler can highlight the terminal tab/pane (iTerm2 and Kitty) to make it easy to find:

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

## Auto-Advance and Auto-Restart

Two control-bar toggles (also bindable as Session List shortcuts) change cycling behavior automatically:

- **Auto-advance**: when the current session goes busy, cycle to the next idle session.
- **Auto-restart**: when all sessions are busy and one becomes idle, jump to it.

---

[← Back to Overview](overview.md)

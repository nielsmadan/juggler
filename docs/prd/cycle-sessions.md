# Cycle Sessions

The core feature of Juggler: cycling through Claude Code sessions using global hotkeys.

## Global Shortcuts

| Shortcut | Action |
|----------|--------|
| `⇧⌘J` | Cycle forward through sessions |
| `⇧⌘K` | Cycle backward through sessions |
| `⇧⌘L` | Backburner current session |
| `⇧⌘H` | Reactivate all backburnered sessions |
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

## Queue Modes

Juggler offers three queue ordering modes, selectable via the segmented control in the popover or main window:

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

## Sectioned Display

Sessions are grouped into sections based on state:

```
┌─────────────────────────────┐
│ Idle (2)                    │  ← Cyclable sessions
│   ● my-feature              │
│   ● api-server              │
├─────────────────────────────┤
│ Busy (1)                    │  ← Working sessions
│   ○ data-pipeline           │
├─────────────────────────────┤
│ Backburner (1)              │  ← Deprioritized
│   ◐ old-project             │
└─────────────────────────────┘
```

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

When cycling to a session, Juggler can highlight the iTerm2 tab/pane to make it easy to find:

### Tab Bar Highlighting

- Flash the tab with a color
- Configurable duration (1-5 seconds)
- Optional: Use cycling colors (each session gets a unique color)

### Pane Background Highlighting

- Flash the pane background with a color
- Useful for split pane layouts
- Same duration and color options as tab highlighting

Settings in **Settings > Highlighting**.

## Go to Next on Backburner

When enabled (default), backburnering automatically cycles to the next idle session. This allows rapid triage: backburner current, immediately see next.

Setting in **Settings > Highlighting > Backburner**.

---

[← Back to Overview](overview.md)

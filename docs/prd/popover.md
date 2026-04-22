# Menu Bar Popover

The menu bar popover is Juggler's primary interface, accessible by clicking the menu bar icon.

## Layout

```
┌──────────────────────────────────────┐
│  Juggler                     ⚙️  📋  │  ← Header with settings & window buttons
├──────────────────────────────────────┤
│  [ Fair ][ Prio ][ Static ][ Grouped ]│  ← Queue mode picker
├──────────────────────────────────────┤
│  ● my-feature              idle  ◀── │  ← Current session indicator
│  ● api-server (1/2)        idle      │  ← Split pane indicator
│  ○ api-server [2/2]      working     │
│  ◐ juggler            backburner     │
├──────────────────────────────────────┤
│  ⇧⌘J/K cycle  ⇧⌘L backburner        │  ← Shortcut hints
└──────────────────────────────────────┘
```

## Header

- **Title:** "Juggler"
- **Settings button** (⚙️): Opens Settings window
- **Window button** (📋): Opens Session Monitor window

## Queue Mode Picker

Segmented control to switch between queue modes:
- **Fair**: Return-to-idle goes to bottom
- **Prio**: Return-to-idle goes to top
- **Static**: Original order
- **Grouped**: Static order, grouped by window

See [Cycle Sessions](cycle-sessions.md#queue-modes) for details.

## Session List

Each row shows:
- **State icon**: `●` idle, `○` working, `◐` backburner, `◎` compacting
- **Display name**: Project folder name or custom name
- **Pane indicator**: `(1/2)` for split panes
- **State label**: "idle", "working", "backburner", etc.
- **Current marker**: `◀──` indicates current cycling position

### Row Coloring

When enabled (Settings > Highlighting > Session List), the currently highlighted row is drawn in a color from a 5-color palette. Only one row is highlighted at a time, and the same color is applied to the terminal tab/pane. See [Highlight Color](highlight-color.md) for the rules that govern when the color changes.

## Interactions

### Click

Single click on a session row:
- Activates the session in the terminal (iTerm2 or Kitty)
- Focuses the corresponding tab and pane
- Optionally highlights the tab/pane (if enabled)
- Closes the popover

### Keyboard Navigation

When popover is focused:
- `↑`/`↓` or `J`/`K`: Navigate session list
- `Return`: Activate selected session
- `L`: Backburner selected session
- `R`: Rename selected session
- `Shift+L`: Reactivate selected (if backburnered)
- `H`: Reactivate all backburnered

### Context Menu (Right-Click)

- **Rename**: Set custom display name
- **Backburner** / **Reactivate**: Toggle backburner state
- **Remove**: Remove session from tracking

## Shortcut Hints

Bottom section shows commonly used shortcuts:
- Navigation shortcuts
- Backburner shortcut
- Mode cycling shortcuts

Can be hidden via Settings > Shortcuts > Show Shortcut Helper.

## Empty State

When no sessions are tracked:
```
┌──────────────────────────────────────┐
│  Juggler                     ⚙️  📋  │
├──────────────────────────────────────┤
│                                      │
│          No sessions                 │
│                                      │
└──────────────────────────────────────┘
```

---

[← Back to Overview](overview.md)

# Menu Bar Popover

The menu bar popover is Juggler's primary interface, accessible by clicking the menu bar icon.

## Layout

```
┌──────────────────────────────────────┐
│  Juggler                     ⚙️  📋  │  ← Header with settings & window buttons
├──────────────────────────────────────┤
│  [ Fair ][ Prio ][ Static ][ Grouped ]│  ← Queue mode picker
├──────────────────────────────────────┤
│  ◉ my-feature                   idle │  ← Highlighted (currently active) row
│  ◉ api-server                   idle │
│  ◉ data-pipeline             working │
│  ◉ juggler                backburner │
├──────────────────────────────────────┤
│  ↑/↓ navigate  L backburner  …       │  ← Shortcut hints
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
- **State icon**: an SF Symbol per state (idle/permission, working, backburner, compacting)
- **Display name**: Project folder name or custom name
- **SSH badge**: an "SSH" tag for remote sessions (hover shows user@host)
- **State label**: "idle", "working", "backburner", etc.

The currently active / keyboard-selected row is shown with a highlight background rather than a separate marker.

### Row Coloring

When enabled (Settings > Highlighting > Session List), the currently highlighted row is drawn in a color from a 5-color palette. Only one row is highlighted at a time, and the same color is applied to the terminal tab/pane. See [Highlight Color](highlight-color.md) for the rules that govern when the color changes.

## Menu Bar Icon

Left-clicking the icon opens the popover; right-clicking opens a menu with **Open Juggler**, **Settings…**, **Check for Updates…**, and **Quit**.

The icon also reflects iTerm2 daemon health:

- **Normal** — full opacity, no tooltip.
- **Connecting** — tooltip "Connecting to iTerm2…".
- **Waiting for iTerm2** — dimmed to 50% opacity, tooltip "Waiting for iTerm2 — make sure it's running and the Python API is enabled."
- **Failed** — tinted red, tooltip "iTerm2 integration unavailable." plus the failure reason.

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

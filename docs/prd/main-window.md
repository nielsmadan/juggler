# Session Monitor Window

The Session Monitor is a standalone window providing an expanded view of all sessions with additional details and statistics.

## Opening the Window

- **Global shortcut:** `⇧⌘;` (customizable)
- **From popover:** Click the window button (📋) in header
- **From menu bar:** Right-click menu bar icon > "Open Monitor"

## Layout

```
┌─────────────────────────────────────────────────────────────┐
│  Session Monitor                                    ⚙️      │
├─────────────────────────────────────────────────────────────┤
│  [ Fair ][ Prio ][ Static ]                                 │
├─────────────────────────────────────────────────────────────┤
│  Idle (2)                                                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ ● my-feature                              2m idle       ││
│  │   ~/Projects/my-feature                                 ││
│  │   Last: "Can you add tests for the login component?"    ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │ ● api-server [1/2]                        5m idle       ││
│  │   ~/Projects/api-server                                 ││
│  │   Last: "Fix the authentication middleware"             ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  Busy (1)                                                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ ○ data-pipeline                           working       ││
│  │   ~/Projects/data-pipeline                              ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  ▶ Idle: 7m  Airtime: 23m           42% idle    ⏹️  ⏸️     │
└─────────────────────────────────────────────────────────────┘
```

## Sections

Sessions are grouped into collapsible sections:

### Idle Section

- Sessions in `idle` or `permission` state
- Shows count in header
- Highlighted when cycling

### Busy Section

- Sessions in `working` or `compacting` state
- Shows count in header

### Backburner Section

- Sessions in `backburner` state
- Shows count in header
- Collapsed by default

## Session Cards

Each session shows expanded information:

| Field | Description |
|-------|-------------|
| **State icon** | Visual state indicator |
| **Display name** | Project folder or custom name |
| **Pane info** | `[1/2]` for split panes |
| **Time info** | Duration in current state |
| **Project path** | Full path to project directory |
| **Last message** | Most recent user prompt (truncated) |
| **Git info** | Branch name and repo (if available) |

## Stats Footer

When enabled (Settings > General > Enable Stats), shows session statistics:

### Metrics

- **Idle time**: Total time sessions have spent waiting
- **Airtime**: Total time sessions have spent working
- **Idle %**: Percentage of sessions currently idle

### Controls

- **Stop button** (⏹️): Reset stats to zero
- **Play/Pause button** (⏸️): Pause/resume stats tracking

### Idle Status Coloring

When enabled, the footer background color indicates idle percentage:
- **Green**: Low idle % (sessions are working)
- **Red**: High idle % (many sessions waiting)

## Keyboard Shortcuts

When window is focused:

| Shortcut | Action |
|----------|--------|
| `↑`/`↓` or `J`/`K` | Navigate sessions |
| `Return` | Activate selected session |
| `B` | Backburner selected |
| `R` | Rename selected |
| `A` | Reactivate selected |
| `Shift+A` | Reactivate all |
| `S` | Toggle stats pause |
| `Shift+R` | Reset stats |

## Interactions

### Click Session

- Activates session in iTerm2
- Focuses corresponding tab/pane
- Optionally highlights tab/pane

### Double-Click Session

- Same as click, plus closes window

### Drag and Drop

- Reorder sessions manually (in Static mode)

### Context Menu

Right-click on session:
- Rename
- Backburner / Reactivate
- Copy project path
- Remove

## Window Behavior

- Remembers position and size
- Can be kept on top (Window menu > Keep on Top)
- Standard macOS window controls (minimize, zoom, close)

---

[← Back to Overview](overview.md)

# Session Monitor Window

The Session Monitor is a standalone window providing an expanded view of all sessions with additional details and statistics.

## Opening the Window

- **Global shortcut:** `⇧⌘;` (customizable)
- **From popover:** Click the window button (📋) in header
- **From menu bar:** Right-click menu bar icon > "Open Juggler"

## Layout

```
┌─────────────────────────────────────────────────────────────┐
│  [ Fair ][ Prio ][ Static ][ Grouped ] │ ⏩  ⟳  💡           │  ← Control bar
├─────────────────────────────────────────────────────────────┤
│  Idle                                                        │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ [icon] my-feature  [✎]                          idle    ││
│  │ [CC ]  📁 ~/Projects/my-feature                          ││
│  │        ⎇ feature/login                                   ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │ [icon] api-server  [✎]                          idle    ││
│  │ [CC ]  📁 ~/Projects/api-server                          ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  Working                                                     │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ [icon] data-pipeline  [✎]                     working   ││
│  │ [CC ]  📁 ~/Projects/data-pipeline                       ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  ▁▂▅▇ ▃  2/4 busy                          busy time by day  │  ← Stats chart
└─────────────────────────────────────────────────────────────┘
```

## Empty State

With no tracked sessions, the window shows a "No Sessions" placeholder: *"Start or continue a session and it will show up here. Codex sessions appear after your first message."*

## Control Bar

A single bar at the top combines the queue mode picker with three toggle buttons:

- **Queue mode picker** — Fair / Prio / Static / Grouped.
- **Auto-advance** (`forward.fill`) — Go to the next session when the current one goes busy.
- **Auto-restart** (`autostartstop`) — When all sessions are busy and one becomes idle, jump to it.
- **Beacon** (`light.panel`) — Show the session-name beacon when cycling.

A dismissible hint ("Hover over buttons to show help.") appears below the bar until dismissed.

## Sections

In Fair and Prio modes, sessions are grouped into three labelled sections — **Idle**, **Working**, and **Backburner** — each with an empty-state placeholder when it has no sessions. Static mode shows a flat list; Grouped mode groups sessions by terminal window.

### Idle Section

- Sessions in `idle` or `permission` state
- Highlighted when cycling

### Working Section

- Sessions in `working` or `compacting` state

### Backburner Section

- Sessions in `backburner` state

## Session Cards

Each session row shows:

| Field | Description |
|-------|-------------|
| **Agent column** | Terminal-type icon, agent initials, and an "SSH" badge for remote sessions (hover shows user@host) |
| **State icon + label** | Visual state indicator and its text label |
| **Display name** | Project folder or custom name, with an inline rename (pencil) button |
| **Project path** | Full path to project directory |
| **Git branch** | Branch name (if available) |

When stats are enabled, each card shows up to two trapezoid tabs in its corner: a **"Turn"** tab with the live duration of the current working turn (only while the session is working or compacting), and an always-present **"Today"** tab with that session's total busy time for the day.

## Stats Chart

When enabled (Settings > General > Stats), the footer shows a bar chart of **busy time per day** (busy time summed across all sessions). Today is the rightmost bar and grows live; older days fall off the left edge. An overlay shows the live "N/M busy" count and a "busy time by day" caption. Bars use per-day palette colors when "Use cycling colors" is on, otherwise the custom bar color; the chart has no stop/pause controls.

## Keyboard Shortcuts

When window is focused (defaults shown; all configurable in Settings > Shortcuts):

| Shortcut | Action |
|----------|--------|
| `↑`/`↓` or `J`/`K` | Navigate sessions |
| `Tab`/`Shift+Tab` | Cycle queue mode forward/backward |
| `Return` | Activate selected session |
| `L` | Backburner selected |
| `R` | Rename selected |
| `Shift+L` | Reactivate selected |
| `H` | Reactivate all |
| `B` | Toggle beacon |
| `A` | Toggle auto-advance |
| `Q` | Toggle auto-restart |

## Interactions

### Click Session

- Activates session in the terminal (iTerm2 or Kitty)
- Focuses corresponding tab/pane
- Optionally highlights tab/pane

### Rename

- Click the inline pencil button on a row, or use the Rename shortcut.

### Context Menu

Row context menus live in the popover (right-click a session row); the monitor window uses the inline pencil button and keyboard shortcuts for rename / backburner / reactivate. Removing a session is available from the popover row context menu (Remove).

## Window Behavior

- Remembers position and size across launches.
- Hidden title bar; content-sized window with standard close/minimize controls.
- Optionally quits the app when closed (Settings > General > "Quit when Session Monitor is closed").

---

[← Back to Overview](overview.md)

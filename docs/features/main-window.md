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
│  │ [icon] my-feature                       idle  [✎]      ││
│  │ [CC ]  📁 ~/Projects/my-feature      claude-opus-4 [💬]   ││
│  │        ⎇ feature/login               high                 ││
│  │        Finish the API error states                        ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │ [icon] api-server                        idle  [✎]     ││
│  │ [CC ]  📁 ~/Projects/api-server      claude-opus-4 [💬]   ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  Working                                                     │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ [icon] data-pipeline                   working [✎]     ││
│  │ [CC ]  📁 ~/Projects/data-pipeline   gpt-5          [💬]  ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  ▁▂▅▇ ▃  2/4 busy                          busy time by day  │  ← Stats chart
└─────────────────────────────────────────────────────────────┘
```

## Empty State

With no tracked sessions, the window shows a "No Sessions" placeholder: *"Start or continue a session and it will show up here. Codex and Antigravity sessions appear after your first message."*

## Control Bar

A single bar at the top combines the queue mode picker with four toggle buttons:

- **Queue mode picker**: Fair / Prio / Static / Grouped.
- **Permission First** (`hand.raised.fill`) - In Fair and Prio modes, keep permission sessions above idle sessions. The control is disabled in Static and Grouped modes, which preserve fixed session ordering.
- **Auto-advance** (`forward.fill`) - Go to the next session when the current one goes busy.
- **Auto-restart** (`autostartstop`) - When all sessions are busy and one becomes idle, jump to it.
- **Beacon** (`light.panel`) - Show the session-name beacon when cycling.

A dismissible hint ("Hover over buttons to show help.") appears below the bar until dismissed.
Using a control-bar toggle, queue-mode choice, or row action button shows a transient hint for its keyboard equivalent.
Directly selecting a queue mode suggests the shortest cycling direction (`Tab` or `Shift+Tab`).
Hints appear at the top center of the monitor window and remain above an open rename sheet.

## Sections

In Fair and Prio modes, sessions are grouped into three labelled sections - **Idle**, **Working**, and **Backburner**: each with an empty-state placeholder when it has no sessions. Static mode shows a flat list; Grouped mode groups sessions by terminal window.

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
| **State icon + label** | Visual state indicator and its text label, centered in the area above the stats tabs |
| **Display name** | Name per the Session Title setting (default: parent / folder name) or a custom name |
| **Row actions** | Compact, top-aligned vertical rename and note buttons at the row's right edge; each can be hidden independently |
| **Row details** | Up to four small labelled values in a 2x2 grid under the name; see below |
| **Note** | One tail-truncated line below the row details, shown only when a note exists |

The note button uses an outlined text bubble when empty and a filled bubble when a note exists. It opens a single-line editor; press `Return` to save or `Escape` to cancel. Rows without a note reserve no empty space.

The rename and note buttons can each be hidden from Settings > General > Session Monitor; the same section chooses the four row details and can shorten project paths under your home directory to `~/...`.

### Row details

The grid has four slots: top left, top right, bottom left, bottom right. Each shows one value, chosen in Settings > General > Session Monitor > Row details. Defaults: Folder Path, Model, Git Branch, Effort. A value an agent does not report leaves its cell empty, so rows stay aligned. A grid row whose two slots are both None, or all four None, is not drawn.

Options: None, Folder Path, Folder Name, Parent / Folder Name, Tab Title, Window Title, Agent Session Title, Git Branch, Model, Effort, Permission Mode, Current Tool, Last Problem, Subagents, Context %, Turns, Run Time. Which agents report which values is in [Agent Session Metadata in Hooks](../reference/agent-session-metadata.md#row-slots-per-agent).

- **Permission Mode** shows labels such as Default, Plan, Accept Edits, Bypass, Auto, Don't Ask; unknown modes are split on `-` and `_` with each word capitalized.
- **Last Problem** shows the last failed turn, for example "Rate limited" or "Interrupted", until the next turn starts.
- **Subagents** and **Turns** are hidden at zero. Turns is the number of prompts the conversation has started, counted by hooklinesinker, so it is right even when Juggler starts mid-session and starts again at 0 after `/clear`. For Antigravity Juggler counts the turns it sees itself. OpenCode reports no turns.
- **Run Time** is how long the agent process has been running, refreshed every 30 seconds.
- **Current Tool** is the tool in use and clears when the turn ends. **Context %** shows "N% context".
- Cells truncate to one line (Folder Path in the middle); hover shows the full text.
- The two columns are always equal width. `SessionSlotGrid` uses a custom `EqualColumnsLayout` rather than `Grid`, because a `Grid` sizes columns to their content and the left and right cells would drift between rows. Trailing reserves are padding inside the layout: both rendered grid rows leave room for the right-edge control rail, and the bottom row also uses the wider stats-tab reserve when needed. The stats reserve is `max(0, cornerWidth - rowHorizontalPadding) + 4` because the corner sits partly inside the row padding and 4 points keep text off the tab border (`SessionRowGeometry`). Whether a trailing cell is under 40 points is decided from measured widths, so a new row can draw one frame with that cell blank.
- The state badge is centered vertically in the space above the stats tabs, or in the full row when stats are off. The action stack is top-aligned in that area. When a right-hand cell would be narrower than about 40 points after its reserve, its text is hidden and appears on hover only.

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
| `M` | Edit note for selected |
| `Shift+L` | Reactivate selected |
| `H` | Reactivate all |
| `B` | Toggle beacon |
| `P` | Toggle permission-first ordering |
| `A` | Toggle auto-advance |
| `Q` | Toggle auto-restart |

## Interactions

### Click Session

- Activates session in the terminal (iTerm2, Kitty, or WezTerm)
- Focuses corresponding tab/pane
- Optionally highlights tab/pane

### Rename

- Click the trailing pencil button on a row, or use the Rename shortcut.

### Notes

- Click the trailing bubble button on a row, or use the Edit Note shortcut.
- Notes persist when the same coding-agent conversation is resumed. A new conversation in the same terminal pane starts without the previous note.

### Context Menu

Row context menus live in the popover (right-click a session row); the monitor window uses trailing action buttons and keyboard shortcuts for rename and notes, plus keyboard shortcuts for backburner / reactivate. Removing a session is available from the popover row context menu (Remove); a removed session stays hidden, including after a restart, until it reports new activity.

## Window Behavior

- Remembers position and size across launches.
- Hidden title bar; content-sized window with standard close/minimize controls.
- Optionally quits the app when closed (Settings > General > "Quit when Session Monitor is closed").

---

[← Back to Overview](overview.md)

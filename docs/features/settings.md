# Settings

The Settings window is organized into tabs, each covering a distinct configuration area.

## General

- **Launch at Login**: Start Juggler automatically when the Mac boots.
- **Show Juggler in Dock**: Toggle the Dock icon (regular vs. accessory activation policy).
- **Quit when Session Monitor is closed**: Quit the app when the monitor window closes.
- **Session Title**: How session names are derived: Tab Title, Window Title, Window / Tab Title, Folder Name, Parent / Folder Name, or Agent Session Title (the title the agent reports, falling back to Parent / Folder Name). The name is global: the monitor, popover, beacon and notifications all use it.
- **Session Monitor**: Pick what each of the four row detail slots shows (top left, top right, bottom left, bottom right; see [Row details](main-window.md#row-details)), choose what each of the three trailing row action slots shows (Rename, Note, Hide, Prio or None; default rename, note, hide), and optionally replace the home directory prefix in shown folder paths with `~` (for example `~/Projects/app`). A None slot removes only the button; `E`, `Y`, `R`, `M` and the top-bar Show Hidden control remain available. Upgrading from the old "Show rename/note/hide button" toggles maps them to slots once at launch: a toggle that was off becomes None. The old `monitorShowRenameButton`, `monitorShowNoteButton` and `monitorShowHideButton` keys stay in `AppStorageKeys` only so this migration can read them. The `~` option applies only while a slot is set to Folder Path. Upgrading from the old "Show folder path" and "Show git branch" toggles maps them to slots once: with both on, Folder Path top left and Git Branch bottom left; with one off, the other takes the top left; with both off, both left slots are None. Model and Effort fill the right slots. The old `monitorShowFolderPath` and `monitorShowBranch` keys stay in `AppStorageKeys` only so this migration can read them; no view uses them.
- **Notifications**: Toggle idle notifications, permission notifications, and sound (see [Notifications](notification.md)).
- **Stats**: Enable Stats (show the busy-time chart in the Session Monitor), plus the stats-bar color: "Use cycling colors" (per-day palette colors) or a custom bar color when off.
- **Backburner**: "Go to next session on backburner" option for rapid triage.
- **Sessions**: "Reset Sessions..." clears every tracked session, the hooklinesinker ledger shared with other apps,
  stale-binding suppression, and saved hidden/backburner dispositions after a confirmation. Conversation notes
  and accumulated busy time are preserved. The list rebuilds from live activity: working sessions reappear within
  seconds, idle ones the next time they run. If hooklinesinker cannot reset its ledger, the error is shown and
  Juggler clears no local rows or dispositions. Use it when the list shows sessions that are not real, for example
  two rows for one terminal pane. See [reset mechanics](../tech/hooks.md#reset-sessions).
- **Uninstall**: Remove all integrations (Claude Code hooks, Kitty watcher, OpenCode plugin), reset the Automation permission, clear settings, and quit.

Permission-first ordering, auto-advance, and auto-restart are toggled from the Session Monitor control bar (and
via Session List shortcuts), not from this tab.

## Integration

The Integration tab is organized into **Permissions**, **Terminals**, **Agents**, and **Tools** groups.

- **Permissions**: Notifications status with a link to System Settings (Automation lives under the iTerm2 terminal section).
- **Terminals**: Kitty (remote control, listen socket, watcher script), iTerm2 (Automation permission), and WezTerm (wezterm CLI status — no configuration needed).
- **Agents**: Install or verify Claude Code hooks, the OpenCode plugin, Codex hooks (including the Codex feature flag
  and trust step), and the Pi extension. The Codex section can ignore permission events so Auto Review does not briefly
  put sessions in the permission queue. This also hides manual Codex permission prompts.
- **Tools**: tmux env forwarding and an SSH Tracking guide (reverse-tunnel setup for tracking Claude Code sessions on remote hosts).

## Highlighting

Controls terminal highlighting when a session is activated. See [Cycle Sessions > Terminal Highlighting](cycle-sessions.md#terminal-highlighting) for behavior.

- **Highlight Triggers**: Independently enable/disable highlighting for hotkey cycling, session select, and notification click.
- **Session List**: "Use cycling highlight colors" to color-code session rows in the popover and monitor.
- **Terminal Highlighting**: A single "Use cycling colors" toggle for both tab and pane, tab bar highlighting (with duration 1/2/3/5 s and a custom tab color when cycling colors are off), and pane highlighting (with its own duration and custom pane color).

## Beacon

Beacon overlay that briefly shows the session name when cycling. When tracked sessions span terminal applications or coding harnesses, successful activation beacons add a terminal/harness subtitle for disambiguation.

- **Position**, **Relative to** (screen or active window), **Size** (XS-XL), **Duration** (0.5-3 s).

The beacon is enabled/disabled from the Session Monitor control bar and the "Toggle Beacon" Session List shortcut, not from this tab.

## Shortcuts

- **Show Shortcut Helper**: Toggle the persistent shortcut reference in the popover and monitor.
- **Show shortcut hints / Hint frequency**: Control transient shortcut hints shown after using shortcut-backed UI.
- **Global hotkeys**: ShortcutKit recorders for all eight global shortcuts (see
  [Cycle Sessions](cycle-sessions.md#global-shortcuts) and [Notifications](notification.md)). Session Menu
  defaults to ⇧⌘M; every binding is customizable.
- **Session List shortcuts**: Configurable ShortcutKit bindings for the popover, the monitor window and the
  [session menu](cycle-sessions.md#session-menu): Activate, Move Down,
  Move Up, Backburner, Send to Back, Reactivate Selected, Reactivate All, Rename, Edit Note (default M), Cycle Mode
  Forward, Cycle Mode Backward, Toggle Beacon, Permission First, Auto Next, Auto Restart.
- **Session Monitor shortcuts**: Hide/Unhide selected (`E`), Show Hidden (`⌘E`) and Prio (`Y`), all without key repeat.
  These apply only while the monitor is the key window. Show Hidden is a launch-scoped view control shared with
  the popover, not a persistent Settings toggle; see [Hide and Show Hidden](main-window.md#hide-and-show-hidden).

## Updates

- Current version display.
- Check for updates now.
- Automatically check for updates (Sparkle).
- Automatically download and install updates (enabled only when auto-check is on).

The standard **App menu > "About Juggler"** opens an About window showing the app icon, version/build, a "Check for Updates…" button, and copyright.

## Logs

- Verbose logging toggle.
- Level and category filters.
- Auto-scroll, copy, and clear controls.

---

[← Back to Overview](overview.md)

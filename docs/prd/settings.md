# Settings

The Settings window is organized into tabs, each covering a distinct configuration area.

## General

- **Launch at login** — Start Juggler automatically when the Mac boots.
- **Notifications** — Toggle idle notifications, permission notifications, sound (see [Notifications](notification.md)).
- **Enable stats** — Show statistics footer in the Session Monitor window.
- **Idle status coloring** — Color the stats footer by idle percentage (green = working, red = idle).
- **Backburner behavior** — "Go to next on backburner" option for rapid triage.
- **Auto-advance on busy** — When the current session goes busy, automatically cycle to the next idle session.
- **Auto-restart on idle** — When a session returns to idle, automatically cycle back to it.
- **Session title mode** — How session names are derived: Tab Title, Window Title, Window/Tab Title, Folder Name, or Parent/Folder Name.

## Integration

- **Permission status** — Accessibility, Automation, and Notifications permissions with links to System Settings.
- **Terminal setup** — Enable/configure iTerm2 and Kitty integrations.
- **Agent hooks** — Install or verify Claude Code, OpenCode, and Codex hooks.

## Highlighting

Controls terminal highlighting when a session is activated. See [Cycle Sessions > Terminal Highlighting](cycle-sessions.md#terminal-highlighting) for behavior.

- **Tab highlight** — Enable, duration (1–5 s), cycling colors or custom color.
- **Pane highlight** — Enable, duration, cycling colors or custom color.
- **Per-trigger toggles** — Independently enable/disable highlighting for hotkey cycling, GUI session select, and notification click.
- **Session list cycling colors** — Color-code session rows in popover and monitor.

## Beacon

Beacon overlay that briefly shows the session name when cycling.

- **Enable**, **position**, **size**, **anchor** (screen or active window).

## Shortcuts

- **Global hotkeys** — Recorders for all six global shortcuts (see [Cycle Sessions](cycle-sessions.md#global-shortcuts) and [Notifications](notification.md)).
- **In-app shortcuts** — Configurable local shortcuts for the popover and monitor window: Move Down, Move Up, Backburner, Reactivate Selected, Reactivate All, Rename, Cycle Mode Forward, Cycle Mode Backward.
- **Show shortcut helper** — Toggle the shortcut hint bar in the popover.

## Updates

- Current version display.
- Check for updates now.
- Auto-check toggle (Sparkle).

## Logs

- Verbose logging toggle.
- Level and category filters.
- Auto-scroll, copy, and clear controls.

---

[← Back to Overview](overview.md)

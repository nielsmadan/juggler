# Settings

The Settings window is organized into tabs, each covering a distinct configuration area.

## General

- **Launch at Login**: Start Juggler automatically when the Mac boots.
- **Show Juggler in Dock**: Toggle the Dock icon (regular vs. accessory activation policy).
- **Quit when Session Monitor is closed**: Quit the app when the monitor window closes.
- **Session Title**: How session names are derived: Tab Title, Window Title, Window / Tab Title, Folder Name, or Parent / Folder Name.
- **Notifications**: Toggle idle notifications, permission notifications, and sound (see [Notifications](notification.md)).
- **Stats**: Enable Stats (show the busy-time chart in the Session Monitor), plus the stats-bar color: "Use cycling colors" (per-day palette colors) or a custom bar color when off.
- **Backburner**: "Go to next session on backburner" option for rapid triage.
- **Uninstall**: Remove all integrations (Claude Code hooks, Kitty watcher, OpenCode plugin), reset the Automation permission, clear settings, and quit.

Auto-advance and auto-restart are toggled from the Session Monitor control bar (and via Session List shortcuts), not from this tab.

## Integration

The Integration tab is organized into **Permissions**, **Terminals**, **Agents**, and **Tools** groups.

- **Permissions**: Accessibility and Notifications status with links to System Settings (Automation lives under the iTerm2 terminal section).
- **Terminals**: Kitty (remote control, listen socket, watcher script) and iTerm2 (Automation permission).
- **Agents**: Install or verify Claude Code hooks, the OpenCode plugin, and Codex hooks (including the Codex feature flag and trust step).
- **Tools**: tmux env forwarding and an SSH Tracking guide (reverse-tunnel setup for tracking Claude Code sessions on remote hosts).

## Highlighting

Controls terminal highlighting when a session is activated. See [Cycle Sessions > Terminal Highlighting](cycle-sessions.md#terminal-highlighting) for behavior.

- **Highlight Triggers**: Independently enable/disable highlighting for hotkey cycling, session select, and notification click.
- **Session List**: "Use cycling highlight colors" to color-code session rows in the popover and monitor.
- **Terminal Highlighting**: A single "Use cycling colors" toggle for both tab and pane, tab bar highlighting (with duration 1/2/3/5 s and a custom tab color when cycling colors are off), and pane highlighting (with its own duration and custom pane color).

## Beacon

Beacon overlay that briefly shows the session name when cycling.

- **Position**, **Relative to** (screen or active window), **Size** (XS-XL), **Duration** (0.5-3 s).

The beacon is enabled/disabled from the Session Monitor control bar and the "Toggle Beacon" Session List shortcut, not from this tab.

## Shortcuts

- **Show Shortcut Helper**: Toggle the shortcut hint bar in the popover and monitor.
- **Global hotkeys**: Recorders for all six global shortcuts (see [Cycle Sessions](cycle-sessions.md#global-shortcuts) and [Notifications](notification.md)).
- **Session List shortcuts**: Configurable local shortcuts for the popover and monitor window: Move Down, Move Up, Backburner, Reactivate Selected, Reactivate All, Rename, Cycle Mode Forward, Cycle Mode Backward, Toggle Beacon, Auto Next, Auto Restart.

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

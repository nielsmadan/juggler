# Juggler - Requirements

## Concept

App to cycle through running Claude Code sessions, see which are idle.

### Main Features

- Global hotkeys to go to next/previous Claude Code session, running inside terminals
- Highlight the terminal window that the session is running in

### USP

- Use your full-featured, existing terminal, keep your existing workflow
- Full flexibility, use any version arrangement, any number of repos, worktrees or not
- Full keyboard controls for every UI element, never need to take your hands off keyboard

### Bells & Whistles

- Main menu bar popover UI to see sessions and select one quickly
- Main window with more information about each session
- Stat measurement: % sessions busy, idle/busy time per session and total

**Target Platform:** macOS 14.0+ (Sonoma), iTerm2

**License:** MIT

---

## Features

### Session Tracking

- Automatic session detection from Claude Code hooks (HTTP server on port 7483)
- Session states: idle, permission, working, compacting, backburner
- Display session name, project path, git branch, state
- Last user message preview
- Terminal tab/window name tracking
- tmux split pane support with per-pane tracking
- Auto-remove stale sessions when terminal tabs close
- Rename sessions with custom names
- Right-click context menu (Rename, Backburner/Reactivate, Remove)

### Queue Modes

| Mode | Behavior |
|------|----------|
| **Fair** | Return-to-idle sessions go to end of queue (round-robin) |
| **Priority** | Return-to-idle sessions go to top (most recent first) |
| **Static** | No reordering, sessions sorted by creation time |

Mode selector available in both popover and main window.

### Global Hotkeys

| Default Shortcut | Action |
|------------------|--------|
| `Shift+Cmd+K` | Cycle forward through idle/permission sessions |
| `Shift+Cmd+J` | Cycle backward |
| `Shift+Cmd+L` | Backburner current session |
| `Shift+Cmd+H` | Reactivate all backburnered sessions |
| `Shift+Cmd+;` | Toggle popover / open main window |

All shortcuts customizable in Settings.

### In-App Keyboard Shortcuts

Configurable local shortcuts for: Move Down, Move Up, Backburner, Reactivate Selected, Reactivate All, Rename, Cycle Mode Forward, Cycle Mode Backward. Plus arrow keys, Enter to activate, S to start/pause stats, R to reset stats.

### Session States

| State | Description | In Cycle? |
|-------|-------------|-----------|
| **Idle** | Waiting for user input | Yes |
| **Permission** | Waiting for user permission | Yes |
| **Working** | Claude is processing | No |
| **Backburner** | Manually deprioritized | No |
| **Compacting** | Session is compacting context | No |

### Terminal Highlighting

- **Tab bar highlighting:** configurable color, duration (1-5s), cycling colors (5-color palette)
- **Pane background highlighting:** separate darker palette, configurable duration
- **Cycling colors:** highlight color matches session's position-based row color in the list
- **Per-trigger toggles:** independently enable/disable highlighting for hotkey cycling, GUI session select, and notification click

### Notifications

- Native macOS notifications when sessions become idle or need permission
- Click notification to activate the session
- Optional sound alerts
- All toggleable in Settings

### Menu Bar Popover

- Session list with state icons
- Queue mode selector
- Current session highlighting with cycling colors
- Click session to activate and switch terminal
- Keyboard navigation
- Shortcut helper (toggleable)
- Quick access to Settings and main window

### Main Window (Session Monitor)

- Sessions organized in three sections: Idle, Busy, Backburner
- Per-session display: icon, name, path, git branch, state, idle/working duration, last user message
- "Group by Window" toggle (Static mode)
- Selection highlighting with position-based cycling colors
- Animated transitions when sessions move between sections:
  - Down: slide out right, off-screen delay, slide in from right
  - Up: smooth vertical movement via matchedGeometryEffect
- Keyboard shortcuts reference grid
- Statistics footer: sessions idle count, total idle time, total airtime, color-coded bar (green=idle, red=busy)

### Statistics

- Per-session: idle time (accumulated), working time (airtime), current idle/working duration
- Global: total idle time, total working time, idle percentage
- Pause/resume and reset controls
- Color-coded footer bar

### Onboarding

1. Welcome screen
2. Accessibility permission (for global hotkeys)
3. iTerm2 runtime setup
4. Default shortcuts overview
5. Claude Code hook installation
6. Finish (launch at login option)

### Settings

**General:** Launch at login, notify on idle, notify on permission, play sound, enable stats, idle status coloring

**Integration:** Permission status display (Accessibility, Automation, Notifications) with links to system preferences. Claude Code hooks install/status. tmux ITERM_SESSION_ID configuration.

**Shortcuts:** Global hotkey recorders. In-app local shortcut recorders. Show shortcut helper toggle.

**Highlighting:** Tab highlight (enable, cycling colors, custom color, duration). Pane highlight (enable, custom color, duration). Per-trigger toggles (hotkey, GUI select, notification). Session list cycling colors. Go to next on backburner.

**Updates:** Version display, check for updates, auto-check toggle (Sparkle).

**Logs:** Verbose logging toggle, level/category filters, auto-scroll, copy/clear logs.

---

## Claude Code Integration

### Hook Events

| Event | Juggler Action |
|-------|----------------|
| `SessionStart` | Register new session |
| `Notification` (idle) | Set state to idle |
| `Notification` (permission) | Set state to permission |
| `UserPromptSubmit` | Set state to working |
| `SubAgentStart` | Set state to working |
| `PreCompact` | Set state to compacting |
| `Stop` | Set state to idle |
| `SessionEnd` | Remove session |

### Hook Payload

Hooks receive JSON via stdin with: `session_id`, `transcript_path`, `cwd`. Hook script enriches with: `iterm_session_id`, `git_branch`, `git_repo`, `tmux_session`, `tmux_pane`.

### iTerm2 Daemon

Python daemon maintaining persistent iTerm2 connection via Unix socket. Commands: activate, highlight, reset_highlight, get_session_info, ping. Pushes focus change events and terminal info updates. Auto-reconnects on connection loss with exponential backoff. Health check heartbeat every 30s.

---

## Future Plans

- Support more terminals: Kitty (need API to access the terminal app, not all terminals have it)
- Support more agentic coding tools: opencode (need hooks for this to work)
- Stretch goal: Windows support

---

## Log

- 22 January: start development
- 6 February: v1.0.0 feature complete

---

## Related Documentation

- [Tech Architecture](tech/overview.md) - Technical implementation details
- [PRD](prd/overview.md) - Product requirements document
- [CLAUDE.md](../CLAUDE.md) - Development documentation

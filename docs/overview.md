# Juggler Documentation

macOS menu bar app for navigating multiple Claude Code sessions in iTerm2 via global hotkeys.

## What is Juggler?

Juggler solves the "context switching" problem when running multiple Claude Code sessions. Instead of manually hunting through terminal tabs, Juggler tracks all your sessions and lets you cycle through the ones that need attention with a single hotkey.

## Key Features

- **Global hotkeys** to cycle through idle sessions (`⇧⌘J`/`⇧⌘K`)
- **Menu bar popover** showing all tracked sessions
- **Backburner queue** to temporarily deprioritize sessions
- **Tab/pane highlighting** to quickly spot the active session
- **Notifications** when sessions become idle or need permission

## How It Works

1. Install hooks into Claude Code (`~/.claude/hooks/`)
2. Hooks notify Juggler when sessions change state
3. Use global hotkeys to jump between sessions
4. Juggler activates the correct iTerm2 tab and pane

## Documentation

### Product

- [**PRD Overview**](prd/overview.md) - Product features and requirements
  - [Cycle Sessions](prd/cycle-sessions.md) - Session cycling and queue modes
  - [Notifications](prd/notification.md) - Notification system
  - [Menu Bar Popover](prd/popover.md) - Popover UI
  - [Main Window](prd/main-window.md) - Session monitor window

### Technical

- [**Tech Overview**](tech/overview.md) - Architecture and components
  - [Hook Server](tech/hook-server.md) - HTTP API for Claude Code hooks
  - [iTerm2 Daemon](tech/iterm2-daemon.md) - Python daemon protocol
  - [Session Management](tech/session-management.md) - Cycling and state logic
  - [Claude Code Hooks](tech/hooks.md) - Hook integration and quirks

### Other

- [Requirements](requirements.md) - Current requirements list

# Juggler Documentation

macOS menu bar app for navigating multiple Claude Code, OpenCode, and Codex sessions in iTerm2 and Kitty via global hotkeys.

## What is Juggler?

Juggler solves the "context switching" problem when running multiple Claude Code, OpenCode, and Codex sessions. Instead of manually hunting through terminal tabs, Juggler tracks all your sessions and lets you cycle through the ones that need attention with a single hotkey.

## Key Features

- **Global hotkeys** to cycle through idle sessions (`⇧⌘J`/`⇧⌘K`)
- **Menu bar popover** showing all tracked sessions
- **Backburner queue** to temporarily deprioritize sessions
- **Tab/pane highlighting** to quickly spot the active session
- **Notifications** when sessions become idle or need permission

## How It Works

1. Install hooks for Claude Code (`~/.claude/hooks/`), OpenCode (a plugin), or Codex (`~/.codex/hooks/`)
2. Hooks notify Juggler when sessions change state
3. Use global hotkeys to jump between sessions
4. Juggler activates the correct terminal tab and pane

## Documentation

### Features (what each does)

- [**Features Overview**](features/overview.md) - What each feature does
  - [Cycle Sessions](features/cycle-sessions.md) - Session cycling and queue modes
  - [Highlight Color](features/highlight-color.md) - Active-session highlight color rules
  - [Notifications](features/notification.md) - Notification system
  - [Menu Bar Popover](features/popover.md) - Popover UI
  - [Main Window](features/main-window.md) - Session monitor window
  - [Beacon](features/beacon.md) - HUD overlay for cycle feedback
  - [Onboarding](features/onboarding.md) - First-launch setup
  - [Settings](features/settings.md) - Settings window reference

### Technical

- [**Tech Overview**](tech/overview.md) - Architecture and components
  - [Hook Server](tech/hook-server.md) - HTTP API for agent hooks
  - [iTerm2 Daemon](tech/iterm2-daemon.md) - Python daemon protocol
  - [iTerm2 Bridge](tech/iterm2-bridge.md) - Daemon supervisor lifecycle and auto-recovery
  - [Terminal Bridges](tech/terminal-bridges.md) - Bridge protocol abstracting terminal APIs
  - [Kitty Integration](tech/kitty-integration.md) - Kitty CLI and watcher integration
  - [Session Management](tech/session-management.md) - Cycling and state logic
  - [Busy-Time Stats](tech/stats.md) - Stats accrual, persistence, and chart/tab layout
  - [Highlight Color](tech/highlight-color.md) - Active-session highlight color implementation
  - [Claude Code Hooks](tech/hooks.md) - Claude Code hook integration and quirks
  - [OpenCode Plugin](tech/opencode-plugin.md) - OpenCode plugin integration
  - [Codex Hooks](tech/codex-hooks.md) - Codex hook integration and trust mechanism


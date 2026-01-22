# Juggler - Product Overview

macOS menu bar app for navigating multiple Claude Code sessions in iTerm2 via global hotkeys.

## What is Juggler?

Juggler monitors Claude Code sessions running in iTerm2 and provides global hotkeys to cycle through sessions needing attention. Users keep their existing terminal setup; Juggler adds keyboard-first navigation.

## Core Workflow

1. **Claude Code hooks** notify Juggler when sessions change state
2. **Menu bar popover** shows all tracked sessions with their current state
3. **Global hotkeys** cycle through sessions needing attention (idle/permission)
4. **Backburner queue** allows deprioritizing sessions you want to ignore temporarily

## Session States

| State | Icon | In Cycle | Description |
|-------|------|----------|-------------|
| `idle` | `●` | Yes | Waiting for user input |
| `permission` | `●` | Yes | Waiting for user permission |
| `working` | `○` | No | Claude is actively working |
| `compacting` | `◎` | No | Context compaction in progress |
| `backburner` | `◐` | No | Manually deprioritized by user |

Sessions in `idle` and `permission` states are included in the cycling queue. Working and backburnered sessions are excluded.

## Feature Documentation

- [Cycle Sessions](cycle-sessions.md) - Session cycling, queue modes, backburner
- [Notifications](notification.md) - Notification system and settings
- [Menu Bar Popover](popover.md) - Popover UI and interactions
- [Main Window](main-window.md) - Session monitor window

## Related Documentation

- [Tech Architecture](../tech/overview.md) - Technical implementation details
- [Requirements](../requirements.md) - Current requirements

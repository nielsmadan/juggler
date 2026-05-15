# Juggler - Product Overview

macOS menu bar app for navigating multiple Claude Code, OpenCode, and Codex sessions in iTerm2 and Kitty via global hotkeys.

**Target platform:** macOS 14.0+ (Sonoma), iTerm2, Kitty. **License:** MIT.

## What is Juggler?

Juggler monitors Claude Code, OpenCode, and Codex sessions running in iTerm2 or Kitty and provides global hotkeys to cycle through sessions needing attention. Users keep their existing terminal setup; Juggler adds keyboard-first navigation.

## Unique Selling Points

- Use your full-featured, existing terminal — keep your existing workflow.
- Full flexibility: any repo arrangement, any number of worktrees, any split-pane layout.
- Full keyboard controls for every UI element — never take your hands off the keyboard.

## Core Workflow

1. **Agent hooks** (Claude Code, OpenCode, Codex) notify Juggler when sessions change state
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
- [Highlight Color](highlight-color.md) - Rules for the active-session highlight color
- [Notifications](notification.md) - Notification system and settings
- [Menu Bar Popover](popover.md) - Popover UI and interactions
- [Main Window](main-window.md) - Session monitor window
- [Beacon](beacon.md) - HUD overlay for cycle feedback
- [Onboarding](onboarding.md) - First-launch setup flow
- [Settings](settings.md) - Settings window reference

## Future Plans

- Stretch goal: Windows support

## Related Documentation

- [Tech Architecture](../tech/overview.md) - Technical implementation details

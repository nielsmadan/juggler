# Juggler

**One hotkey. Next idle session.**

A native macOS menu bar app that tracks your running coding agent sessions and cycles you to the next one that needs attention. No workflow changes. No new terminal. Just less time wasted.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![MIT License](https://img.shields.io/badge/license-MIT-green) ![Claude Code](https://img.shields.io/badge/Claude_Code-supported-brightgreen) ![OpenCode](https://img.shields.io/badge/OpenCode-supported-brightgreen) ![iTerm2](https://img.shields.io/badge/iTerm2-supported-brightgreen) ![Kitty](https://img.shields.io/badge/Kitty-supported-brightgreen)

<p align="center">
  <img src="site/video.gif" alt="Juggler demo" width="720">
</p>

## Why Juggler

- **Instant switching** — Press one global hotkey from anywhere and Juggler takes you straight to the next session waiting for input
- **Never lose a window** — Color-coded tab and pane highlighting lets you spot the active session immediately, even across monitors
- **Zero workflow changes** — No new terminal to learn, no forced worktrees, no single-repo limits. Your existing setup stays exactly as it was

## Installation

### Homebrew (recommended)

```bash
brew install --cask nielsmadan/juggler/juggler
```

### Manual download

Download the latest DMG from [GitHub Releases](https://github.com/nielsmadan/juggler/releases/latest/download/Juggler.dmg). Open the DMG and drag Juggler to Applications.

## Getting Started

1. **Download and open** — Launch Juggler from Applications
2. **Walk through onboarding** — Grant Accessibility permissions, set up terminal integration, install hooks
3. **Open your sessions** — Start Claude Code or OpenCode as you normally would. Juggler detects them automatically
4. **Hit the hotkey** — Press `⇧⌘K` and you're at the next idle session

## Features

- **Global hotkeys** — Cycle forward, backward, backburner, reactivate, toggle UI — all from any app, all customizable
- **Tab & pane highlighting** — Cycling color palette marks the active session's tab and pane
- **Notifications** — Native macOS alerts when a session goes idle or needs permission. Click to jump there
- **Menu bar & monitor** — Popover for a quick glance. Full session monitor window with animated state transitions and stats
- **Queue modes** — Fair (round-robin), Priority (most recent first), Static (creation order), or Grouped (by state)
- **Backburner** — Park sessions you don't need right now. They stay tracked but won't appear in your cycle
- **Idle time stats** — Per-session and global idle vs. working time
- **Guided setup** — Onboarding walks you through permissions, terminal integration, and hook installation

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⇧⌘K` | Cycle to next idle session |
| `⇧⌘J` | Cycle backward |
| `⇧⌘L` | Backburner current session |
| `⇧⌘H` | Reactivate all backburnered sessions |
| `⇧⌘;` | Toggle popover / open monitor |

All shortcuts are customizable in Settings.

## Compatibility

**Terminals:** iTerm2, Kitty, tmux (optional multiplexer)

**Coding agents:** Claude Code, OpenCode

**Requires:** macOS 14.0+ (Sonoma)

## How It Works

Juggler runs a lightweight HTTP server on port 7483 that receives state-change events from your coding agent. When a session goes idle, starts working, or needs permission, Juggler updates its tracking and can notify you or cycle you to sessions that need attention.

**Terminal integration:** For iTerm2, a Python daemon communicates via iTerm2's Python API over a Unix socket, providing session switching, tab highlighting, and focus tracking. For Kitty, Juggler uses `kitten @` remote control commands.

**Session states:** idle, permission, working, compacting, backburner

## Agent Integration

Juggler's onboarding flow sets up agent integration automatically. You can also configure it manually:

- **Claude Code** — Shell hooks installed to `~/.claude/hooks/juggler/`. Alternatively, run `/Applications/Juggler.app/Contents/Resources/install.sh`
- **OpenCode** — TypeScript plugin installed to `~/.config/opencode/plugins/juggler-opencode.ts`. Configure via Settings → Integrations

## Your Terminal. Your Way.

Other session managers wrap your sessions in a TUI or custom terminal — you give up your splits, profiles, colors, scrollback, and muscle memory in exchange for a dashboard.

Juggler sits in your menu bar. Detects sessions via hooks. Activates and highlights your real terminal windows natively. Your workflow stays exactly as it was — just with less time spent hunting for idle sessions.

## Development

- [CLAUDE.md](CLAUDE.md) — Development documentation and build instructions
- [docs/tech/overview.md](docs/tech/overview.md) — Technical architecture
- [docs/requirements.md](docs/requirements.md) — Feature requirements

## License

MIT License — see [LICENSE](LICENSE) for details.

# Juggler

**Get into the agentic coding flow.**

A native macOS app that tracks your running coding agent sessions and cycles you to the next one that needs attention. No workflow changes. No new terminal. Just less time wasted.

Currently works with iTerm2 / Kitty (tmux optional) and Claude Code / OpenCode. More integrations coming soon.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![MIT License](https://img.shields.io/badge/license-MIT-green) ![Claude Code](https://img.shields.io/badge/Claude_Code-supported-brightgreen) ![OpenCode](https://img.shields.io/badge/OpenCode-supported-brightgreen) ![iTerm2](https://img.shields.io/badge/iTerm2-supported-brightgreen) ![Kitty](https://img.shields.io/badge/Kitty-supported-brightgreen)

<p align="center">
  <img src="site/video.gif" alt="Juggler demo" width="720">
</p>

Yes, you can configure it to always use the same color or disable the tab/pane highlighting completely, but where's the fun in that?

## Why Juggler

I usually have 3-6 terminals open, each of which will have 2-6 tabs focused on various repos. I was constantly
either alt tabbing around or taking my hands off the keyboard to find the next session. Then after a while I would
realize that there was some session that just needed me to press enter that I completely forgot about. All the
solutions I found for this force you to use their workflow, requiring worktrees or tmux,
limiting to one repo, and making you use some embedded SwiftTerminal. I didn't want that. I wanted to keep my workflow
and the terminal I already set up just the way I like. So I built Juggler.

### What sets it apart:

- **Instant switching** — Press one global hotkey from anywhere and Juggler takes you straight to the next session waiting for input
- **Never lose a window** — Color-coded tab and pane highlighting lets you spot the active session immediately, even across monitors
- **Zero workflow changes** — No new terminal to learn, no forced worktrees, no single-repo limits. Your existing setup stays exactly as it was

### Who I am

I have more than 15 years of software development experience working professionally in TypeScript / Python / C++. This is not
slopcode / slopware.

## Installation

### Homebrew (recommended)

```bash
brew install --cask nielsmadan/juggler/juggler
```

### Manual download

[Download the latest DMG](https://github.com/nielsmadan/juggler/releases/latest/download/Juggler.dmg), open it, and drag Juggler to Applications.

## Getting Started

1. **Download and open** — Launch Juggler from Applications
2. **Walk through onboarding** — Grant Accessibility permissions, set up terminal integration(s), install hooks
3. **Open your sessions** — Start Claude Code or OpenCode as you normally would. Juggler detects them automatically
4. **Hit the hotkey** — Press `⇧⌘K` and you're at the next idle session

## Features

- **Global hotkeys** — Cycle forward, backward, backburner, reactivate, toggle UI — all from any app, all customizable
- **Tab & pane highlighting** — Cycling color palette marks the active session's tab and pane
- **Notifications** — Native macOS alerts when a session goes idle or needs permission. Click to jump there
- **Menu bar & monitor** — Popover for a quick glance. Full session monitor window with jugglery animations and stats
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

## Future

### Terminals

Juggler requires terminals with a scriptable API to switch sessions and highlight tabs/panes. Support for additional terminals depends on whether they expose one.

**Planned:**

- [WezTerm](https://wezfurlong.org/wezterm/) — cross-platform CLI API for session and tab control (macOS, Linux, Windows)

**Waiting on API support:**

- [Ghostty](https://github.com/ghostty-org/ghostty) — no scripting API yet ([discussion](https://github.com/ghostty-org/ghostty/discussions/2353))
- [Warp](https://www.warp.dev/) — no plugin system yet ([discussion](https://github.com/warpdotdev/Warp/discussions/435))
- [Alacritty](https://alacritty.org/) — minimal by design, no session control API
- Terminal.app — AppleScript support too limited for tab/pane management

### Coding Agents

Juggler tracks agent sessions through lifecycle hooks that fire on events like session start, tool use, and idle. Support for additional agents depends on their hook systems.

**Planned:**

- [Gemini CLI](https://github.com/google-gemini/gemini-cli) — has comprehensive hooks (SessionStart/End, BeforeTool/AfterTool)
- [GitHub Copilot CLI](https://github.com/github/copilot-cli) — has hooks (sessionStart/End, preToolUse)

**Waiting on hook support:**

- [Codex CLI](https://github.com/openai/codex) — only has `agent-turn-complete` notify, no session lifecycle hooks ([discussion](https://github.com/openai/codex/discussions/2150))
- [Aider](https://github.com/Aider-AI/aider) — no lifecycle hooks

### Linux & Windows

Juggler is currently macOS-only. [WezTerm](https://wezfurlong.org/wezterm/) runs on macOS, Linux, and Windows with a CLI API for session control, and [Kitty](https://sw.kovidgoyal.net/kitty/) already runs on Linux. If there's popular demand, I'm happy to port it.

## Development

- [CLAUDE.md](CLAUDE.md) — Development documentation and build instructions
- [docs/tech/overview.md](docs/tech/overview.md) — Technical architecture
- [docs/requirements.md](docs/requirements.md) — Feature requirements

## License

MIT License — see [LICENSE](LICENSE) for details.

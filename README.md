# Juggler

A macOS menu bar app for navigating Claude Code sessions in iTerm2 via global hotkeys.

## Features

- **Session Tracking** - Automatically tracks Claude Code sessions via hooks
- **Global Hotkeys** - Cycle through sessions without leaving your keyboard
- **Smart Filtering** - Focus on sessions that need attention (idle or waiting for permission)
- **Backburner Mode** - Temporarily hide sessions you're not actively working on
- **Tab Highlighting** - Visual feedback when switching between sessions
- **Notifications** - Get alerted when sessions need your attention

## Requirements

- macOS 14.0 or later
- iTerm2

## Installation

1. Download the latest release
2. Move `Juggler.app` to your Applications folder
3. Launch Juggler from Applications
4. Grant Accessibility permissions when prompted (required for global hotkeys)
5. Run the onboarding flow to install Claude Code hooks

## Usage

### Global Hotkeys

| Hotkey | Action |
|--------|--------|
| `Shift+Cmd+J` | Jump to next idle/permission session |
| `Shift+Cmd+K` | Jump to previous idle/permission session |
| `Shift+Cmd+L` | Send current session to backburner |
| `Shift+Cmd+H` | Reactivate all backburner sessions |
| `Shift+Cmd+;` | Show/hide session monitor window |

### Menu Bar

Click the Juggler icon in the menu bar to:
- View all active sessions and their status
- Click a session to switch to it
- Access preferences and quit

### Session States

- **Idle** - Claude is waiting for input
- **Working** - Claude is currently processing
- **Permission** - Claude needs permission to proceed
- **Backburner** - Session temporarily hidden from cycling

## Installing Claude Code Hooks

Juggler tracks sessions through Claude Code's hook system. The onboarding flow will install hooks automatically, but you can also install them manually:

### Automatic Installation

Run the install script bundled with Juggler:
```bash
/Applications/Juggler.app/Contents/Resources/install.sh
```

### Manual Installation

1. Create the hooks directory:
   ```bash
   mkdir -p ~/.claude/hooks/juggler
   ```

2. Copy the `notify.sh` script from Juggler's Resources folder to `~/.claude/hooks/juggler/`

3. Add hooks to `~/.claude/settings.json`:
   ```json
   {
     "hooks": {
       "SessionStart": [{
         "hooks": [{"type": "command", "command": "~/.claude/hooks/juggler/notify.sh start", "timeout": 5}]
       }],
       "Notification": [{
         "matcher": "idle_prompt|permission_prompt",
         "hooks": [{"type": "command", "command": "~/.claude/hooks/juggler/notify.sh idle", "timeout": 5}]
       }],
       "UserPromptSubmit": [{
         "hooks": [{"type": "command", "command": "~/.claude/hooks/juggler/notify.sh working", "timeout": 5}]
       }],
       "Stop": [{
         "hooks": [{"type": "command", "command": "~/.claude/hooks/juggler/notify.sh stop", "timeout": 5}]
       }]
     }
   }
   ```

## How It Works

Juggler runs a lightweight HTTP server on port 7483 that receives events from Claude Code hooks. When a session changes state, Juggler updates its internal tracking and can notify you or help you navigate to sessions that need attention.

The app communicates with iTerm2 via a Python daemon using iTerm2's Python API over a Unix socket. This provides fast, reliable session switching and tab highlighting.

## Development

- [CLAUDE.md](CLAUDE.md) - Development documentation and build instructions
- [docs/tech/overview.md](docs/tech/overview.md) - Technical architecture
- [docs/requirements.md](docs/requirements.md) - Feature requirements

## License

MIT License - see [LICENSE](LICENSE) for details.

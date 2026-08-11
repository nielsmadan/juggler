# Onboarding

First-launch flow that walks new users through the setup required for Juggler to work.

## Steps

1. **Welcome**: Brief intro to what Juggler does.
2. **Accessibility Permission**: Required for global hotkeys. Links to System Settings.
3. **Integration Hub**: Terminal setup (iTerm2, Kitty, and/or WezTerm), optional tmux env forwarding, and agent hook
   installation (Claude Code, OpenCode, Codex, Pi, Antigravity). Codex setup includes an option to ignore permission
   events so Auto Review does not briefly put sessions in the permission queue. It is preselected when Auto Review is
   detected in the global Codex config.
4. **Global Shortcuts**: Recorders for the six global hotkeys (Cycle Forward/Backward, Backburner Current, Reactivate All, Show Monitor, Last Notification). Users can accept defaults or customize.
5. **Finish**: Options to enable "Launch at Login" and "Automatically download and install updates".

## Behavior

- Triggered automatically on first launch.
- Can be re-opened later from the Help menu (for reconfiguration or testing).
- All shortcuts chosen here are also customizable in Settings > Shortcuts.

---

[← Back to Overview](overview.md)

# Notifications

Juggler uses macOS system notifications to alert users when sessions need attention.

## Notification Types

### Session Idle

Triggered when a session transitions to idle state (waiting for user input).

- **Title:** "Session Idle"
- **Body:** Session display name (project folder or custom name)
- **When:** Claude finishes a response and waits for next prompt

### Permission Required

Triggered when a session requests user permission to proceed.

- **Title:** "Permission Required"
- **Body:** Session display name
- **When:** Claude needs approval for a tool use or action

## Settings

All notification settings are in **Settings > General > Notifications**:

| Setting | Default | Description |
|---------|---------|-------------|
| Notify when session becomes idle | On | Send notification on idle state |
| Notify when session needs permission | On | Send notification on permission state |
| Play sound | On | Play system sound with notifications |

## Behavior

- Notifications are sent once per state transition, not repeatedly: a session that is already idle
  or waiting for permission does not notify again when its agent reports the same state (for example
  while a subagent keeps working during a permission prompt)
- Backburnered and hidden sessions do not trigger notifications, even with Show Hidden on
- Clicking a notification activates the corresponding session in the terminal (iTerm2, Kitty, or WezTerm)
- A global hotkey (Shift+Cmd+E by default) jumps to the session from the most recent notification, even after the banner is dismissed
- Notifications respect macOS Do Not Disturb settings
- Hiding invalidates banners already created for that row and its Last Notification target. Clicking an old banner
  cannot activate it, even after Unhide. Removing or replacing the conversation also invalidates its target.

## Implementation Notes

- Uses `UNUserNotificationCenter` for macOS notifications
- Sound uses system notification sound when enabled
- Notification permission requested on first launch if needed
- Delivery callbacks and activation recheck the same generation-bound conversation target; stale completions cannot
  become Last Notification. See [activation and notifications](../tech/session-management.md#activation-and-notifications).

---

[← Back to Overview](overview.md)

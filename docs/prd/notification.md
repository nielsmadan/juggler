# Notifications

Juggler uses macOS system notifications to alert users when sessions need attention.

## Notification Types

### Session Idle

Triggered when a Claude Code session transitions to idle state (waiting for user input).

- **Title:** "Session Idle"
- **Body:** Session display name (project folder or custom name)
- **When:** Claude finishes a response and waits for next prompt

### Permission Required

Triggered when a Claude Code session requests user permission to proceed.

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

- Notifications are sent once per state transition, not repeatedly
- Backburnered sessions do not trigger notifications
- Clicking a notification activates the corresponding session in iTerm2
- Notifications respect macOS Do Not Disturb settings

## Implementation Notes

- Uses `UNUserNotificationCenter` for macOS notifications
- Sound uses system notification sound when enabled
- Notification permission requested on first launch if needed

---

[← Back to Overview](overview.md)

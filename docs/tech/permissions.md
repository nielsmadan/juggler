# macOS Permissions

Which system permissions Juggler actually requires, and why the others are deliberately absent.
The distinction matters because the permissions look interchangeable in System Settings but are
granted for very different capabilities.

## Required

**Automation** — load-bearing. iTerm2 control goes through Apple Events, which is what the
Automation grant covers. Surfaced in Settings under the iTerm2 terminal section, and reset by
Uninstall.

**Notifications** — for idle and permission notifications.

## Deliberately not required

**Accessibility.** Global shortcuts register through Carbon (`ShortcutKitGlobal`), not an event
tap. Terminal control uses Apple Events, terminal APIs and CLIs, sockets, localhost hooks, and
`NSWorkspace` notifications. None of those cross the AX boundary.

The permission check and its onboarding step, Settings row, and reset behavior came from the
project's root scaffold rather than from a requirement, and were removed in `31ad40a`
(2026-08-20) with no shortcut or terminal implementation change. Restore them only if code adds
real AX APIs, global event taps or posting, or System Events UI scripting.

Users who ran an earlier build may still have a vestigial Juggler entry under Accessibility. It
is harmless and grants nothing that Juggler uses.

**Input Monitoring.** Same reasoning: Carbon registration does not monitor input.

**Screen Recording.** Beacon window anchoring reads only owner PID, bounds, and layer, none of
which are gated. Reading window *names* would cross into Screen Recording territory and change
this.

---

[← Back to Tech Overview](overview.md)

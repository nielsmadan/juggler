# Beacon

The beacon is a brief HUD overlay that shows the current session name whenever the user cycles between sessions. It answers "which session am I on now?" without requiring the user to look at the terminal tab bar or open Juggler.

## Behavior

### When it appears

- `⇧⌘K` — cycle forward → beacon shows next session name
- `⇧⌘J` — cycle backward → beacon shows previous session name

Cycling while no cyclable session exists shows the fallback label **"All At Work"**.

The beacon does **not** appear for:
- Manual session clicks in the popover or main window
- Backburner / reactivate actions
- External terminal focus changes

### What it shows

A single line: the session's display name. White text on solid black with a 2 px white border, medium font weight. Long names truncate in the middle.

### Duration

Configurable: 0.5, 1.0, 1.5 (default), 2.0, or 3.0 seconds. The beacon fades out over 0.3 s after the timer expires.

### Rapid cycling

Each new `show()` cancels the pending dismiss task, swaps the content to the new name, and restarts the timer. The user sees a continuous beacon whose text updates in place — no stacking, no flicker.

## Settings

`Settings → Beacon`:

| Control | Options |
|---------|---------|
| Enable | On / Off |
| Position | Center, Top Left, Top Right, Bottom Left, Bottom Right |
| Relative to | Screen (default), Active Window |
| Size | XS, S, M (default), L, XL |
| Duration | 0.5 / 1.0 / 1.5 / 2.0 / 3.0 seconds |

All controls disable when the beacon is off.

### Size

Size scales font, padding, and minimum width. XS uses 16 px text and a 100 px min width; XL uses 52 px text and a 320 px min width; S / M / L scale between. Max width is capped at 600 px; height auto-fits content.

### Position and anchor

`Center` positions at center. Corner options offset 40 px from the edges.

`Relative to`:
- **Screen** — anchored to `NSScreen.main`.
- **Active Window** — anchored to the frontmost app's window bounds. Useful in multi-monitor setups where the beacon should follow the current workspace.

## Technical Notes

Implementation:
- `Managers/BeaconManager.swift` — show/dismiss coordination, panel lifecycle
- `Views/BeaconContentView.swift` — SwiftUI content
- `Views/BeaconSettingsView.swift` — settings UI

Models:
- `BeaconPosition` — 5 cases (center + 4 corners)
- `BeaconAnchor` — `screen` or `activeWindow`
- `BeaconSize` — xs / s / m / l / xl
- `BeaconPositionCalculator.calculateOrigin()` — translates position + anchor + size into an `NSPoint` (40 px edge margin)

Window: a single reused `NSPanel` (borderless, transparent, non-activating, floating). `canJoinAllSpaces` and `fullScreenAuxiliary` ensure it appears on every Space and over fullscreen apps.

Animation: 0.2 s fade-in, 0.3 s fade-out via `alphaValue`.

Triggers: `HotkeyManager.handleCycleForward()` (`HotkeyManager.swift:123`) and `handleCycleBackward()` (`HotkeyManager.swift:135`).

## Edge Cases

- **Beacon disabled** — `show()` returns early; the panel is never created.
- **No cyclable session** — fallback label "All At Work" is shown.
- **Rapid hotkey presses** — `showGeneration` counter (`BeaconManager.swift:11`) invalidates stale dismiss tasks so only the latest timer runs.
- **Multi-monitor** — `Screen` anchor uses `NSScreen.main`; `Active Window` follows the frontmost app. No mirroring across displays.
- **Manual dismissal** — not supported; the beacon always auto-dismisses.

---

[← Back to PRD Overview](overview.md)

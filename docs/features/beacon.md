# Beacon

The beacon is a brief HUD overlay that shows the current session name whenever the user cycles between sessions. When active sessions span terminals or coding harnesses, it also identifies the target terminal and harness. It answers "which session am I on now?" without requiring the user to look at the terminal tab bar or open Juggler.

## Behavior

### When it appears

- `⇧⌘K` - cycle forward → beacon shows next session name
- `⇧⌘J` - cycle backward → beacon shows previous session name

Cycling while no cyclable session exists shows the fallback label **"All At Work"**.

On a *successful* activation the beacon does **not** appear for:
- Manual session clicks in the popover or main window
- Backburner / reactivate actions
- External terminal focus changes

### Activation failure

When the user requests an activation that **fails** for any reason - a missing/unreachable terminal, a dead bridge, a daemon error - the beacon flashes the fallback label **"Activation Failed"** so the failure isn't silent. This is forced: it appears even when the beacon is disabled in Settings, and it covers every user-initiated activation path (hotkey cycle, go-to-notification, backburner advance, manual clicks, and notification clicks). Skipping a stale session mid-cycle is not a failure - the cycle silently advances to the next live session and only the successful landing (or "All At Work") is shown.

### What it shows

The session's display name appears as the title. Successful activations add a centered subtitle when the tracked sessions need disambiguation:

- More than one terminal application: the target terminal name, such as `iTerm2` or `Kitty`.
- More than one coding harness: the target harness name, such as `Claude Code` or `Codex`.
- Both vary: terminal first, as in `iTerm2 · Claude Code`.

These conditions are independent and count every tracked session, including backburnered sessions. Fallback beacons such as "All At Work," "No Notification," and "Activation Failed" remain title-only.

The title uses medium white text. The subtitle uses regular white text at half the configured title size, with a 10 pt minimum. Both are single-line, centered, and truncate in the middle on a solid black panel with a 2 px white border.

### Duration

Configurable: 0.5, 1.0, 1.5 (default), 2.0, or 3.0 seconds. The beacon fades out over 0.3 s after the timer expires.

### Rapid cycling

Each new `show()` cancels the pending dismiss task, swaps the content to the new name, and restarts the timer. The user sees a continuous beacon whose text updates in place - no stacking, no flicker.

## Enabling / disabling

The beacon is enabled or disabled from the Session Monitor control bar (the `light.panel` toggle) and the "Toggle Beacon" Session List shortcut (default `B`), not from the Settings window. The `Settings → Beacon` tab only exposes appearance options; those controls grey out while the beacon is off.

## Settings

`Settings → Beacon`:

| Control | Options |
|---------|---------|
| Position | Center, Top Left, Top Right, Bottom Left, Bottom Right |
| Relative to | Screen (default), Active Window |
| Size | XS, S, M (default), L, XL |
| Duration | 0.5 / 1.0 / 1.5 / 2.0 / 3.0 seconds |

### Size

Size scales title and subtitle fonts, padding, and minimum width. XS uses a 16 pt title and 10 pt subtitle with a 100 px min width; XL uses a 52 pt title and 26 pt subtitle with a 320 px min width; S / M / L scale between. Max width is capped at 600 px; height auto-fits content.

### Position and anchor

`Center` positions at center. Corner options offset 40 px from the edges.

`Relative to`:
- **Screen**: anchored to `NSScreen.main`.
- **Active Window**: anchored to the frontmost app's window bounds. Useful in multi-monitor setups where the beacon should follow the current workspace.

## Technical Notes

Implementation:
- `Managers/BeaconManager.swift` - show/dismiss coordination, panel lifecycle
- `Views/BeaconContentView.swift` - SwiftUI content
- `Views/BeaconSettingsView.swift` - settings UI

Models:
- `BeaconPosition` - 5 cases (center + 4 corners)
- `BeaconAnchor` - `screen` or `activeWindow`
- `BeaconSize` - xs / s / m / l / xl
- `BeaconMetadata` - resolves optional terminal and harness subtitles from all tracked sessions
- `BeaconPositionCalculator.calculateOrigin()` - translates position + anchor + size into an `NSPoint` (40 px edge margin)

Window: a single reused `NSPanel` (borderless, transparent, non-activating, floating). `canJoinAllSpaces` and `fullScreenAuxiliary` ensure it appears on every Space and over fullscreen apps.

Animation: 0.2 s fade-in, 0.3 s fade-out via `alphaValue`.

Triggers: every activation surface goes through `SessionActivator`, whose presentation policy resolves metadata and calls `BeaconManager.show(...)` on successful cycle and go-to-last-notification landings. "All At Work," "No Notification," and forced "Activation Failed" calls omit the subtitle.

## Edge Cases

- **Beacon disabled**: `show()` returns early; the panel is never created.
- **No cyclable session**: fallback label "All At Work" is shown.
- **Rapid hotkey presses**: `showGeneration` counter (`BeaconManager.swift:11`) invalidates stale dismiss tasks so only the latest timer runs.
- **Multi-monitor**: `Screen` anchor uses `NSScreen.main`; `Active Window` follows the frontmost app. No mirroring across displays.
- **Manual dismissal**: not supported; the beacon always auto-dismisses.

---

[← Back to Overview](overview.md)

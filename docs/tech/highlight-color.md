# Session Highlight Color — Implementation

Behavioral rules for the active-session highlight color live in the PRD: [Session Highlight Color](../prd/highlight-color.md). This document covers where the rules are implemented.

## Source of truth

`SessionManager.activeColorIndex` (Int) is the single source of truth. It indexes into `CyclingColors.palette` (5 colors) for SwiftUI highlights and into `CyclingColors.paletteRGB` / `CyclingColors.darkPaletteRGB` for terminal tab / pane highlights.

Readers:

- `SessionMonitorView` and `SessionRowView` read `SessionManager.activeColor` (computed accessor that applies the defensive modulo).
- `TerminalBridge.sessionColorIndex(for:)` returns `activeColorIndex` and feeds the `HighlightConfig` sent to iTerm2 / Kitty.

## Writers

All mutations go through `SessionManager`. No other type writes to `activeColorIndex` directly.

| Method | When it fires | PRD rule |
|---|---|---|
| `advanceColorIndex(by:)` | Cycling (hotkey, arrow keys, Tab). Wraps modulo palette size. | 1, 4 |
| `setColorIndex(to:)` | Explicit position — click on a row, external focus change syncing to that row. | 2 |
| `syncColorIndex(toSessionID:)` | Click-path helper: looks up the session's row and calls `setColorIndex`. No-op if unknown or already matching. | 2 |
| `clearColorIndex()` | Session list empty, or selection cannot be recovered. | 11 |

## Cycling engine coupling

`CyclingEngine.cycleForward` / `cycleBackward` return `CyclingResult.didMove` (true iff more than one cyclable session). `SessionManager.cycleForward` / `cycleBackward` only call `advanceColorIndex` when `didMove == true`, implementing rule 4.

## Activation guard

`SessionManager.activationTarget` is set via `beginActivation` for the duration of a cycle / click activation. While non-nil, `SessionListController.setSelection` skips `setColorIndex` on focus-resync events. This is what makes activation atomic (rule 6): the color that cycling or a click just set isn't clobbered by a stray focus event during the flight.

## Relevant files

- `juggler/Managers/SessionManager.swift` — color state and mutators (`activeColorIndex`, `activeColor`, `advanceColorIndex`, `setColorIndex`, `clearColorIndex`, `syncColorIndex`).
- `juggler/Models/CyclingEngine.swift` — cycling algorithm; emits `didMove`.
- `juggler/Models/AppConstants.swift` — `CyclingColors.palette`, `paletteRGB`, `darkPaletteRGB` (rule 7).
- `juggler/Views/SessionListController.swift` — arrow / Tab navigation, reorder sync (rule 3), external focus handling.
- `juggler/Views/SessionMonitorView.swift` — main-window row highlight and click-to-activate.
- `juggler/Views/SessionRowView.swift` — popover row highlight and click-to-activate.
- `juggler/Services/TerminalBridge.swift` — builds `HighlightConfig` from `activeColorIndex`.

---

[← Back to Overview](overview.md)

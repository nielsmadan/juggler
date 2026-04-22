# Session Highlight Color

Juggler marks one session at a time as "active" with a color drawn from a 5-color palette. The same color shows on the monitor row, the popover row, and the terminal tab / pane — the three surfaces always agree.

## Core rules

1. **Cycling** — global hotkey, arrow keys in the monitor, `J` / `K` in the popover — advances the color by one step. The new color travels with you to the newly-selected session.
2. **Activating a specific session** — clicking a row in the monitor or popover, or the terminal integration telling us focus jumped to a tracked session — sets the color to that session's current row position. Terminal and monitor match immediately.
3. **Reordering** — state transitions, queue mode changes — does not change the color. The highlighted session keeps its color as it moves up or down the list.

## Edge cases

4. **Single-session cycling doesn't change the color.** Cycling when only one session is cyclable is a no-op and leaves the color alone. Arrow keys in the full monitor always advance the color, because they navigate the full list (not just the cyclable subset).
5. **Re-activating the current row preserves color.** Pressing Enter on the keyboard-selected row, or re-clicking the already-selected row, does not bounce the color.
6. **Activation is atomic.** While a cycle or click is in flight, stray focus events (e.g. a terminal app bringing itself to the foreground and briefly landing on the wrong tab) do not alter the color. The color that cycling or the click set is what sticks.
7. **Tab and pane share a hue.** The terminal tab highlight is bright; the pane background highlight is a darker variant of the same color.
8. **Color is ephemeral.** Juggler does not remember the color across app launches — it always starts from the first color in the palette.
9. **Highlight only shows when meaningful.** The colored row appears when a tracked terminal is focused, or when the monitor window is key. Otherwise no row is colored.
10. **Per-surface toggles.** The monitor / popover highlight and the terminal tab highlight have independent cycling-color toggles. Turning one off falls back to the accent (or a user-picked custom color) for that surface only.
11. **Graceful recovery.** If the highlighted session is removed from the list, selection falls back to the same row position (if still valid) or the first row. If the list becomes empty, the color resets.

## Related

- [Cycle Sessions](cycle-sessions.md) — hotkeys, queue modes
- [Menu Bar Popover](popover.md)
- [Main Window](main-window.md)
- Implementation: [tech/highlight-color.md](../tech/highlight-color.md)

---

[← Back to Overview](overview.md)

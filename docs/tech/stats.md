# Busy-Time Stats

Implementation of the busy-time tracking subsystem: per-session accrual, per-day persistence, and the chart/corner-tab layout. For the user-facing product view (what the chart looks like and the settings that control it), see [docs/prd/main-window.md](../prd/main-window.md).

## Contents

- [Overview](#overview)
- [Data model](#data-model)
- [Accrual: how busy time is measured](#accrual-how-busy-time-is-measured)
- [Persistence: DailyStatsStore](#persistence-dailystatsstore)
- [Midnight rollover](#midnight-rollover)
- [Chart rendering: StatsChartView](#chart-rendering-statschartview)
- [Bar layout: StatsBarLayout](#bar-layout-statsbarlayout)
- [Per-row tabs: BusyStatsCorner](#per-row-tabs-busystatscorner)
- [Gotchas](#gotchas)

## Overview

"Busy time" = wall-clock time a session spends in `working` or `compacting`. Two states count as busy throughout; `idle`/`permission`/`backburner` do not.

Three layers:

- **Accrual** — `SessionManager` watches state transitions and converts busy stretches into committed `TimeInterval` deltas.
- **Persistence** — `DailyStatsStore` buckets those deltas into a `[dayKey: seconds]` map, JSON-encoded into `UserDefaults`.
- **Display** — `StatsChartView` (the day chart) and `BusyStatsCorner` (per-row Turn/Today tabs) read both the persisted totals and the live in-progress turns.

The store knows nothing about sessions; the views own all "live" arithmetic by adding in-progress turns on top of the persisted base.

## Data model

Per-session busy-time fields live on `Session` (`Session.swift:25-26`):

- `lastBecameWorking: Date?` — wall-clock start of the *current* busy stretch, `nil` when not busy. Acts as both a flag and a timestamp.
- `busyTimeToday: TimeInterval` — committed busy time accrued by this session *today* (excludes the in-progress stretch).

Two derived accessors (`Session.swift:121-130`):

- `currentWorkingDuration` — `nil` unless busy; otherwise `now - lastBecameWorking`. The live in-progress turn.
- `busyTimeTodayLive` — `busyTimeToday + (currentWorkingDuration ?? 0)`. This session's today total including the open turn.

`DailyBusyEntry` (`DailyStatsStore.swift:4-9`) is the chart-facing per-day record (`key`, decoded `date`, `seconds`).

## Accrual: how busy time is measured

All accrual happens in `SessionManager.handleStateTransition` (`SessionManager.swift:161-175`), driven off the `working`/`compacting` membership of the old vs. new state:

- **Entering busy** (`!wasWorking && isWorking`): stamp `lastBecameWorking = now`. Nothing is committed yet — the stretch is only counted once it closes.
- **Leaving busy** (`wasWorking && !isWorking`): compute `now - lastBecameWorking`, add it to both `session.busyTimeToday` *and* `dailyStats.addBusyTime(...)`, then clear `lastBecameWorking`.

So a delta is committed exactly once, at the moment the session stops being busy. `working ↔ compacting` transitions are *not* boundaries — both are busy, so the membership check is false on both sides and the open stretch carries across without a commit. The initial `lastBecameWorking` is also set when a session is first created busy (`SessionManager.swift:655`).

`commitInProgressBusyTime` (`SessionManager.swift:319-330`) is a best-effort flush for in-progress stretches at app termination — called from `applicationShouldTerminate` (`JugglerApp.swift:21`). It commits the elapsed turn for every still-busy session and clears `lastBecameWorking` to prevent double-counting. Because it runs synchronously before the async teardown, a clean quit doesn't lose the open turn. A *crash* loses the uncommitted stretch — there is no incremental persistence of the open turn.

### Why commit-on-close rather than tick-on-interval

There's no per-second timer accruing into the store. The store only ever sees closed deltas (plus the termination/rollover flushes). The live display reconstructs the open turn on the fly from `lastBecameWorking`, so the persisted numbers stay monotonic and tick-free.

## Persistence: DailyStatsStore

`DailyStatsStore` (`DailyStatsStore.swift`) is an `@Observable` passive store:

- **Shape**: `dailyBusySeconds: [String: TimeInterval]`, JSON-encoded into `UserDefaults` under `AppStorageKeys.dailyBusyStats` (= `"dailyBusyStats"`, `AppStorageKeys.swift:21`). Encoded/decoded with `JSONEncoder`/`JSONDecoder`; a decode failure falls back to an empty map.
- **Day key**: `"yyyy-MM-dd"` via a `DateFormatter` pinned to `en_US_POSIX` + current calendar/timezone (`DailyStatsStore.swift:22-29`, `dayKey(for:)` at `:42`). The POSIX locale keeps the format stable across user locale changes; lexical sort of these keys equals chronological order, which `recentDays` relies on (`:69`).
- **Write**: `addBusyTime(_:on:)` (`:48`) adds a delta into the day bucket for `date` and persists. It guards `seconds > 0`, so non-positive deltas are dropped — *a zero-busy day never gets an entry*.
- **Read**: `busySeconds(for:)` / `todayBusySeconds` for point lookups; `recentDays(limit:)` (`:64`) returns the most recent `limit` days *that have data*, oldest→newest, as `DailyBusyEntry`s.

Every `addBusyTime` call persists immediately (`persist()` at `:73`) — there's no batching. Write volume is low (one write per closed busy stretch + rollover/termination), so this is fine.

History is never pruned; the map grows one key per worked day indefinitely.

## Midnight rollover

`handleDayRolloverIfNeeded(now:)` (`SessionManager.swift:297-314`) handles local-midnight crossing. `lastSeenDay` (`SessionManager.swift:21`) tracks the start-of-day last observed; the function early-returns unless `startOfDay(now) > lastSeenDay`.

On a crossing, for each session:

- If it's still busy with a `lastBecameWorking` before the new day, the pre-midnight portion (`newDay - lastBecameWorking`) is committed to **`lastSeenDay`** (the day that just ended), and `lastBecameWorking` is reset to `newDay` so the post-midnight portion accrues to the new day.
- `busyTimeToday` is reset to `0` for *every* session (the per-session "today" counter restarts).

Then `lastSeenDay = newDay`.

### What drives the tick

Rollover is **not** driven by a background timer in `SessionManager`. It's driven by the monitor window: `StatsChartView` owns a 5-second `Timer.publish` (`StatsChartView.swift:20`) and calls `sessionManager.handleDayRolloverIfNeeded(now:)` from `.onReceive` (`:37-39`).

**Implication**: rollover only fires while the monitor window is open and rendering. If the window is closed across midnight, the split doesn't happen at midnight — it happens whenever the window next renders (or never, if the app quits first, in which case the termination flush commits the whole stretch to whatever day `now` is). The `lastSeenDay` guard makes this idempotent: a late tick still correctly splits at the *true* boundary because `lastBecameWorking` and `lastSeenDay` carry the real timestamps. But intervening fully-elapsed days that were never observed don't get their own buckets — the catch-up commits only the one pre-`newDay` slice to `lastSeenDay`.

## Chart rendering: StatsChartView

`StatsChartView` (`StatsChartView.swift`) renders the per-day bar chart in the monitor footer (`SessionMonitorView.swift:252`).

- **Live refresh**: wrapped in a `TimelineView(.periodic(by: 5))` (`:30`) so today's bar grows without explicit invalidation. The separate `rolloverTimer` (`:20`, mutated only in `.onReceive`, never in `body`) handles the day boundary.
- **Data assembly** (`displayEntries`, `:133-156`): takes `recentDays(limit: 60)`, then forces a today entry to always exist as the rightmost bar (even at 0 seconds) so the chart has a stable right anchor. Today's `seconds` is overwritten with `liveTodaySeconds`.
- **Live today total** (`liveTodaySeconds`, `:126-129`): `dailyStats.todayBusySeconds` (persisted committed total) **plus** the sum of every session's `currentWorkingDuration` (open turns). This is the only place the chart adds in-progress time — the store itself never holds it.
- **Bar heights** are normalized against `max(visible seconds)`, floored at `barMinHeight` (`:73`) so a near-zero day still shows a foot under its duration label.
- **Color**: per-date stable index (`colorIndex`, `:181-187`) keyed off day-count from a fixed reference date, so window resizing never reshuffles hues. Today's bar is full-strength; older bars are dimmed by `StatsChart.barDimFactor`. Cycling-palette vs. fixed custom color is an `@AppStorage` toggle.
- **Duration labels** use `SessionStatsCalculator.formatDuration` (`SessionStatsCalculator.swift:14`) — `0m` / `<1m` / `Xm` / `XhYYm` / `XdYYh`.

## Bar layout: StatsBarLayout

`StatsBarLayout.layout(...)` (`StatsBarLayout.swift:11`) is pure geometry — "fit N min-width bars from the right, then clamp":

1. **Fit count**: `fit = ⌊(availableWidth + gap) / (minWidth + gap)⌋` — the most `minWidth` bars that fit including inter-bar gaps. Final `count = clamp(fit, 1...dayCount)`, so the chart shows at most as many bars as there are days with data.
2. **Even width**: once `count` is fixed, divide the remaining width evenly (`(availableWidth - (count-1)*gap)/count`), then clamp to `[minWidth, maxWidth]`.

When the clamp hits `maxWidth` (few days in a wide window), the leftover space is simply unused — bars don't stretch past `maxWidth`. `StatsChartView` passes `availableWidth = width - 24` (12pt padding each side, `:45`) and the `StatsChart` constants (`minWidth 56`, `maxWidth 80`, `gap 6`, `AppConstants.swift:56-66`). The view then renders `entries.suffix(count)` (`:53`) — the layout decides *how many* fit, the view takes that many from the right.

Today's bar "growing live" is purely the height path (live `seconds` → normalized height); layout width is independent of busy time.

## Per-row tabs: BusyStatsCorner

`BusyStatsCorner` (`BusyStatsCorner.swift`) renders the two trapezoid tabs at the bottom-right of a session row (`SessionMonitorView.swift:403`, `:450`). Also wrapped in a 5s `TimelineView` (`:22`) for live ticking.

- **Turn tab** — shown *only* while busy: gated on `session.currentWorkingDuration != nil` (`:24`), which is `nil` unless `working`/`compacting`. Displays the live current-turn duration. Transitions in/out via a move+opacity animation keyed on `currentWorkingDuration != nil` (`:50`).
- **Today tab** — *always* present (`:36`): displays `session.busyTimeTodayLive` (committed today + open turn).

Both format via `SessionStatsCalculator.formatDuration`. The Today tab is rendered last so its diagonal left edge cleanly overlays the Turn tab tucked beneath it; the negative `HStack` spacing (`-tabOverlap`) and `tabDiagonalOffset` (`AppConstants.swift:69-77`) make the two slants kiss without a gap. Today's rendered width is reported up via `TodayTabWidthKey` (`:5-10`) so the row's state badge can center-align on the tab's apex. Shape geometry: `TabShape` (filled trapezoid) and `TabBorderShape` (open diagonal+top "shelf" outline) at `:105` / `:122`.

## Gotchas

- **A day total can exceed 24h.** Busy time is summed across *concurrent* sessions, so N sessions busy for an hour each contribute N hours to the same bucket. The chart, the today total, and per-day persistence all reflect this — it's intentional, not a bug.
- **Zero-busy days are never stored.** `addBusyTime` drops non-positive deltas, so an unworked day has no map entry. `recentDays` therefore returns a *gapless* list of only worked days — **there is no calendar gap-filling**. Adjacent bars in the chart can be non-consecutive calendar days. The only synthesized entry is today, which `displayEntries` always forces in (even at 0) as the right anchor.
- **Rollover depends on the monitor window.** The 5s rollover tick lives in `StatsChartView`, not in `SessionManager`. With the window closed across midnight, the split is deferred until the next render; if the app quits first, the termination flush attributes the whole open stretch to the quit-time day. The `lastSeenDay` + real-timestamp design keeps the eventual split correct, but un-observed intermediate days get no buckets.
- **Open turns are never persisted incrementally.** Only closed stretches (state-leave, rollover split, termination flush) write to the store. A crash loses the current in-progress turn.
- **Live arithmetic lives in the views, not the store.** `DailyStatsStore` holds only committed totals. `liveTodaySeconds` (chart) and `busyTimeTodayLive` (row) each independently add open turns. Don't expect `todayBusySeconds` to match what's on screen while sessions are busy.

---

[← Back to Tech Overview](overview.md)

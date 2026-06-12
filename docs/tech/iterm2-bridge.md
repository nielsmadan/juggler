# iTerm2 Bridge: Supervisor & Daemon Robustness

**Purpose:** Document the lifecycle, readiness, recovery, and self-healing machinery layered on top of the iTerm2 daemon — the supervisor side in `ITerm2Bridge` and the daemon-side monitors/retry logic that keep the integration alive across iTerm2 restarts, transient API failures, and stale connections.

For the socket wire protocol, command/response shapes, the empty-string exception, and zombie-daemon prevention, see [iterm2-daemon.md](iterm2-daemon.md). For the cross-terminal `TerminalBridge` protocol and `TerminalActivation` orchestration, see [terminal-bridges.md](terminal-bridges.md). This doc complements both and does not restate them.

## Table of Contents

- [Swift supervisor (`ITerm2Bridge`)](#swift-supervisor-iterm2bridge)
  - [DaemonState lifecycle](#daemonstate-lifecycle)
  - [Two-phase readiness wait](#two-phase-readiness-wait)
  - [iTerm2 launch/quit observers](#iterm2-launchquit-observers)
  - [Health check & event-listener auto-reconnect](#health-check--event-listener-auto-reconnect)
  - [stderr ring buffer & failure reasons](#stderr-ring-buffer--failure-reasons)
  - [Notification dedup](#notification-dedup)
  - [Timeouts & per-command recovery](#timeouts--per-command-recovery)
- [Daemon side (`iterm2_daemon.py`)](#daemon-side-iterm2_daemonpy)
  - [Three concurrent monitors](#three-concurrent-monitors)
  - [Connection watchdog & structured errors](#connection-watchdog--structured-errors)
  - [Highlight apply retry & reset machinery](#highlight-apply-retry--reset-machinery)
- [UI consumer: StatusBarManager](#ui-consumer-statusbarmanager)
- [Gotchas](#gotchas)

---

## Swift supervisor (`ITerm2Bridge`)

The actor `ITerm2Bridge` (`Services/iTerm2Bridge.swift:63`) owns the daemon subprocess and supervises its lifecycle. Observable state lives in `ITerm2DaemonStatus.shared` (`iTerm2Bridge.swift:18-31`), a `@MainActor @Observable` holding the current `DaemonState` and the last stderr tail — these are what the UI reacts to.

### DaemonState lifecycle

`DaemonState` (`iTerm2Bridge.swift:10-16`) is a five-case enum:

| State | Meaning |
|-------|---------|
| `.stopped` | No daemon running. Initial state and the terminal state after `stop()`. |
| `.starting` | `start()` is in progress — cookie requested, process launched, inside the initial readiness wait. |
| `.waitingForITerm2` | Daemon is up but iTerm2 hasn't answered yet (or iTerm2 just quit). The background startup monitor is polling, or we're idling until iTerm2 relaunches. Non-fatal; UI dims rather than alarms. |
| `.ready` | Daemon answered a ping; event listener and health check are wired. Normal operating state. |
| `.failed(reason:)` | Startup exhausted its window, or the daemon process exited before reaching `.ready`. `reason` carries a stderr-derived message. |

State is set only via `setDaemonState` (`iTerm2Bridge.swift:342`), which hops to `@MainActor` to mutate the observable.

### Two-phase readiness wait

Readiness is split across two phases so the bridge actor isn't blocked for the full timeout (`start()` at `iTerm2Bridge.swift:106`):

- **Phase 1 — initial wait, on the actor (~3s).** After `process.run()`, `start()` calls `waitForDaemonReady` (`iTerm2Bridge.swift:228`) with a deadline of `initialReadinessWait = 3.0` s (`iTerm2Bridge.swift:100`). It polls `daemonPingSucceeds` every 250ms. The common case (iTerm2 already running) returns here and goes straight to `.ready` via `finishStartupReady`.
- **Phase 2 — extended wait, off the actor (~60s).** If phase 1 fails, `start()` transitions to `.waitingForITerm2` and hands off to `runStartupMonitor` (`iTerm2Bridge.swift:247`) as a detached `Task`, then returns immediately so the actor is free. The monitor polls every 1s until `extendedReadinessWait = 60.0` s (`iTerm2Bridge.swift:101`) total (deadline computed as `extendedReadinessWait - initialReadinessWait`). On success it calls `finishStartupReady`; on exhaustion it sets `.failed` with the stderr tail and posts the failure notification.

Readiness is verified by a strict ping round-trip, not socket existence: `daemonPingSucceeds` (`iTerm2Bridge.swift:296`) connects, sends `{"command":"ping"}`, and requires a decoded `status == "ok"`. This avoids false positives from stale socket files or a just-bound-but-not-yet-serving daemon. Both wait loops also bail early if `daemonProcess.isRunning` goes false — the `terminationHandler` records the failure in that case.

**Why:** iTerm2's Python API may be slow to accept connections (or iTerm2 may be launching), so a single short timeout would spuriously fail; a single long synchronous wait would pin the actor for up to a minute. The split keeps the fast path fast and the slow path non-blocking.

### iTerm2 launch/quit observers

`installLifecycleObservers` (`iTerm2Bridge.swift:392`) registers `NSWorkspace` `didLaunch`/`didTerminate` observers filtered to bundle ID `com.googlecode.iterm2` (`iTerm2Bridge.swift:102`). Installation is idempotent (guards on nil); `removeLifecycleObservers` tears them down in `stop()`.

- **iTerm2 launched** → `handleITerm2Launched` (`iTerm2Bridge.swift:433`). If state is `.waitingForITerm2`, `.failed`, or `.stopped`, it calls `restart()`. If already `.starting`/`.ready`, no-op.
- **iTerm2 terminated** → `handleITerm2Terminated` (`iTerm2Bridge.swift:445`). If state is `.ready`, flips to `.waitingForITerm2` for an immediate UI signal. It deliberately does **not** tear down the daemon process — the daemon's own iTerm2 connection will die inside the `iterm2` library and the process will exit, at which point `terminationHandler` handles it. Marking `.waitingForITerm2` early just gives the user a faster status-bar cue.

**Why:** This is the auto-recovery spine. A user can quit and relaunch iTerm2 (or it can crash) and Juggler reconnects without manual intervention.

### Health check & event-listener auto-reconnect

Two background tasks keep the live connection honest:

- **Health check** — `startHealthCheck` (`iTerm2Bridge.swift:593`) loops every 30s sending a ping via `sendRequest`. On failure it logs, and if the event listener has dropped (`eventReadSource == nil`) it triggers `scheduleEventListenerReconnect`.
- **Event listener** — `startEventListener` (`iTerm2Bridge.swift:459`) opens a persistent subscriber socket via a `DispatchSource` read source on a dedicated queue. On EOF or a hard recv error, `handleSocketData` (`iTerm2Bridge.swift:543`) calls `cancelEventListener`, which (while the daemon process is still alive) calls `scheduleEventListenerReconnect` (`iTerm2Bridge.swift:569`).
- **Reconnect with escalation** — `scheduleEventListenerReconnect` retries with a backoff schedule of `[2, 5, 10, 15]` seconds, re-checking that the daemon is alive and the listener hasn't already reconnected each iteration. If all four attempts fail, it escalates to a full `restart()`.

**Why:** The event stream (focus changes, terminal_info, session_terminated) is what keeps `SessionManager` in sync. A silently-dropped subscriber socket would freeze the session list, so the listener self-heals first, then nukes-and-restarts as a last resort.

### stderr ring buffer & failure reasons

The daemon's stderr is captured into a bounded `StderrRingBuffer` (`iTerm2Bridge.swift:37`, default 64 KB capacity) so failure messages have something concrete to show without risking a full-pipe hang:

- The pipe's `readabilityHandler` is installed **before** `process.run()` and drains chunks onto a dedicated queue (`iTerm2Bridge.swift:155-159`). If the pipe filled (the daemon is chatty under iterm2 `retry=True`), the daemon's write would block and silently hang the supervisor — hence eager draining and a ring buffer that drops oldest bytes on overflow.
- The `terminationHandler` (`iTerm2Bridge.swift:164`) drains trailing bytes, snapshots the buffer, and forwards both exit status and the tail to `handleDaemonExit` (`iTerm2Bridge.swift:351`).
- `handleDaemonExit` always refreshes `ITerm2DaemonStatus.shared.lastStderrTail`, then — only if the death wasn't caused by our own `stop()` (guarded by `daemonProcess != nil`) and the state was `.ready`/`.starting`/`.waitingForITerm2` — sets `.failed`, embedding `stderrTail.suffix(500)` into the reason.

The most useful tail line is the daemon's **structured error**: `_emit_structured_error` (`iterm2_daemon.py:488`) writes a single JSON line `{"phase": ..., "detail": ...}` to stderr before exit (connection timeout, fatal). This lands in the ring buffer and surfaces verbatim in the failure reason / tooltip.

### Notification dedup

Two one-shot flags (`iTerm2Bridge.swift:90-91`) prevent notification spam:

- `hasNotifiedWaiting` — set the first time the daemon enters `.waitingForITerm2` (in `transitionToWaiting`, `iTerm2Bridge.swift:279`) and **never reset** for the app's lifetime. Ongoing waits are conveyed ambiently by the dimmed status-bar icon, so the user is nagged at most once.
- `hasNotifiedFailed` — gates `postFailedNotification` (`iTerm2Bridge.swift:371`). It **is** reset, but only in `restart()` (`iTerm2Bridge.swift:712`), so a failed → recovered → failed-again cycle does re-notify (the integration genuinely needs attention again). The waiting flag intentionally stays set across restarts to avoid repeat "waiting" nags.

### Timeouts & per-command recovery

- **Command timeouts** — `withTimeout` (`iTerm2Bridge.swift:861`) races the operation against a sleep that throws `commandTimeout`. `activate` uses `activateTimeout = 2.0` s; `highlight` uses `highlightTimeout = 1.0` s (`iTerm2Bridge.swift:98-99`).
- **Socket-level timeouts** — `sendRequest` (`iTerm2Bridge.swift:881`) sets `SO_RCVTIMEO`/`SO_SNDTIMEO` to 1s; the subscribe ack read has a 3s `SO_RCVTIMEO` (`iTerm2Bridge.swift:530`).
- **Stale-connection recovery** — `shouldAttemptRecovery` (`iTerm2Bridge.swift:689`) classifies errors. `activate` and `getSessionInfo` catch recoverable errors, call `restart()`, and retry once. `highlight` fails silently (cosmetic only). `getSessionInfo` additionally maps a `"session not found"` `commandFailed` to `nil` so `TerminalActivation.isSessionGone` can clean up — see [terminal-bridges.md](terminal-bridges.md#detecting-a-gone-session-from-an-opaque-error).
- **Orphan cleanup** — `start()` first calls `killOrphanedDaemon` (`iTerm2Bridge.swift:658`), which SIGTERMs (then SIGKILLs) the PID recorded in the `.pid` sidecar file from a previous run — but only if `isOrphanedDaemon` confirms it's actually an orphan of ours (parent is launchd **and** its args reference our daemon script + this socket path). The socket/PID files are shared across dev builds, so this guards against killing another build's *live* daemon or a reused PID. `restart()` is `stop()` + 500ms + `start()`.

## Daemon side (`iterm2_daemon.py`)

### Three concurrent monitors

`start()` (`iterm2_daemon.py:36`) spawns three event monitors as concurrent tasks, plus the parent/socket watchers documented in [iterm2-daemon.md](iterm2-daemon.md):

- **`run_focus_monitor`** (`iterm2_daemon.py:159`) — wraps `iterm2.FocusMonitor`; pushes `focus_changed` events. Tolerates transient errors by retrying on the existing connection with a 5s backoff (like `run_layout_monitor`). It does **not** kill the daemon: a transient `FocusMonitor` failure recurs after a restart, so the old "exit after 3 failures" produced a restart loop. Genuine connection-level breakage is recovered by the request path's `restart()` instead.
- **`run_session_monitor`** (`iterm2_daemon.py:184`) — wraps `iterm2.SessionTerminationMonitor`; pushes `session_terminated`. Same 5s retry, but on 3 failures it merely `break`s (gives up) without killing the daemon, because the layout monitor below provides a faster, overlapping signal.
- **`run_layout_monitor`** (`iterm2_daemon.py:206`) — wraps `iterm2.LayoutChangeMonitor`. It snapshots all session IDs (`_get_all_session_ids`, `iterm2_daemon.py:232`), and on each layout change diffs the previous set against the current, emitting `session_terminated` for every ID that disappeared.

**Why `run_layout_monitor` exists:** `SessionTerminationMonitor` only fires once the session's underlying process actually exits, which can lag ~5s after a tab/window is closed. `LayoutChangeMonitor` fires immediately on close, so the layout monitor detects gone sessions much faster. Both feed the same `session_terminated` event; on the Swift side `handleDaemonEvent` (`iTerm2Bridge.swift:723-726`) routes it to `SessionManager.removeSessionsByTerminalID`, so the duplicate-event overlap is harmless (a second removal of an already-gone session is a no-op) and the user sees stale rows vanish promptly.

### Connection watchdog & structured errors

The initial iTerm2 connection is guarded by a SIGALRM watchdog set at module load: `signal.alarm(CONNECTION_TIMEOUT_SECONDS)` with `CONNECTION_TIMEOUT_SECONDS = 30` (`iterm2_daemon.py:485`, `:524-525`). The `iterm2` library run with `retry=True` would otherwise spin forever on connection-refused/401. `main` clears the alarm with `signal.alarm(0)` (`iterm2_daemon.py:504`) the moment the websocket handshake succeeds — after that, daemon uptime is unbounded. On timeout, `_connection_timeout_handler` emits a `connection_timeout` structured error and exits 1; the top-level handler emits a `fatal` structured error for any other startup exception. These JSON stderr lines are exactly what the supervisor's ring buffer surfaces into the `.failed` reason.

### Highlight apply retry & reset machinery

Highlight application is best-effort with a layered fallback in `_apply_profile_with_retry` (`iterm2_daemon.py:382`):

1. Try `async_set_profile_properties`.
2. On failure, wait 1s and retry once.
3. If the retry fails and an `escape_fallback` byte sequence was provided, inject it via `async_inject`.
4. If everything fails, log and give up (highlight is cosmetic).

The reset machinery restores the original appearance after the highlight duration:

- `_reset_tab_after_delay` (`iterm2_daemon.py:404`) sleeps the duration, then clears the tab color (`set_use_tab_color(False)`) via the retry helper (no escape fallback).
- `_reset_pane_after_delay` (`iterm2_daemon.py:415`) restores the captured original background color, with `b'\033]1337;SetColors=bg=default\a'` as the escape-sequence fallback when profile writes fail.
- Both register their task in `active_tab_reset_tasks` / `active_pane_reset_tasks` and `pop` themselves in a `finally`. `highlight_session` (`iterm2_daemon.py:344-350`) cancels any in-flight reset for the same tab/pane before applying a new highlight, so a rapid re-highlight doesn't get clobbered by a stale reset firing mid-flash.

**Why the escape-sequence fallback:** profile-property writes can fail or no-op against a session whose profile state is wedged; injecting the OSC 1337 `SetColors` sequence resets the background directly through the terminal stream, which succeeds in cases the profile API doesn't.

## UI consumer: StatusBarManager

`StatusBarManager` is the sole UI consumer of daemon state. `observeDaemonStatus` (`Managers/StatusBarManager.swift:73`) uses `withObservationTracking` to read `ITerm2DaemonStatus.shared.state` and `.lastStderrTail`, re-arming itself on every change (the `onChange` closure hops to main and re-establishes tracking).

`applyDaemonStatus` (`StatusBarManager.swift:86`) maps state to the menu-bar button's appearance:

| State | Alpha | Tint | Tooltip |
|-------|-------|------|---------|
| `.stopped`, `.ready` | 1.0 | none | none |
| `.starting` | 1.0 | none | "Connecting to iTerm2…" |
| `.waitingForITerm2` | 0.5 (dimmed) | none | "Waiting for iTerm2 — make sure it's running and the Python API is enabled." |
| `.failed(reason)` | 1.0 | `.systemRed` | "iTerm2 integration unavailable.\n{reason}" + `stderrTail.suffix(400)` |

So a healthy daemon is invisible, a waiting daemon dims the icon, and a failed daemon turns it red with a diagnostic tooltip that includes the captured stderr tail.

## Gotchas

- **Self-inflicted death is not a failure.** `stop()` (`iTerm2Bridge.swift:625`) clears `daemonProcess` *first* and detaches the `terminationHandler` before terminating, so a user-initiated quit doesn't trip a `.failed` transition. `handleDaemonExit` also guards on `daemonProcess != nil`.
- **The readiness ping is stricter than socket existence.** Don't "optimize" `daemonPingSucceeds` to a file-existence check — stale sockets and not-yet-serving daemons would read as ready.
- **`hasNotifiedWaiting` never resets; `hasNotifiedFailed` resets only in `restart()`.** Changing this changes user-facing notification frequency.
- **stderr handler must be installed before `process.run()`.** A full pipe blocks the daemon's write and hangs the supervisor.
- **Duplicate `session_terminated` is expected.** The session and layout monitors both emit it; downstream removal is idempotent.
- **No monitor kills the daemon on failure.** Focus and layout monitors retry forever (focus is essential and has no backup); the session monitor gives up after 3 (its layout-monitor backup covers it). An earlier "focus monitor exits after 3 failures to force a restart" was removed — it just looped on transient `FocusMonitor` errors.

---

[← Back to Tech Overview](overview.md)

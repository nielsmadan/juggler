# Terminal Control APIs

What iTerm2, Kitty, WezTerm, and Ghostty expose to an external process that wants to focus a
specific pane, recolor it, and find out whether it still exists.

This file covers the **external** terminals. How Juggler's bridge layer consumes them is in
[`docs/tech/terminal-bridges.md`](../tech/terminal-bridges.md),
[`iterm2-bridge.md`](../tech/iterm2-bridge.md), [`iterm2-daemon.md`](../tech/iterm2-daemon.md),
[`kitty-integration.md`](../tech/kitty-integration.md), and
[`wezterm-bridge.md`](../tech/wezterm-bridge.md).

- [Capability matrix](#capability-matrix)
- [Addressing: how a pane learns its own id](#addressing-how-a-pane-learns-its-own-id)
- [iTerm2](#iterm2)
- [Kitty](#kitty)
- [WezTerm](#wezterm)
- [Ghostty](#ghostty)
- [Cross-terminal gotchas](#cross-terminal-gotchas)
- [Upstream](#upstream)

## Capability matrix

| | iTerm2 | Kitty | WezTerm | Ghostty |
|---|---|---|---|---|
| Control mechanism | Python API over websocket | `kitten @` CLI | `wezterm cli` CLI | **none** |
| Activate a pane | `session.async_activate(...)` | `focus-window --match id:<id>` | `activate-pane --pane-id <id>` | — |
| Query session info | `tab.async_get_variable(...)` | `ls` (nested JSON) | `list --format json` (flat array) | — |
| Set tab color | `set_tab_color` on a profile change | `set-tab-color ... active_bg=<hex>` | **impossible** | — |
| Set pane background | `set_background_color`, OSC fallback | `set-colors ... background=<hex>` | **impossible** | — |
| Focus-change events | `FocusMonitor` (push) | watcher `on_focus_change` (push) | **none** | — |
| Pane-close events | `SessionTerminationMonitor` + `LayoutChangeMonitor` | watcher `on_close` (push) | **none** | — |
| Setup burden | enable Python API, grant Automation | edit `kitty.conf`, install watcher, restart | none | — |

Note the shape of the trade: WezTerm is the easiest to reach (no config, no daemon, no permission
prompt) and the least capable. iTerm2 is the most capable and the most demanding to set up.

## Addressing: how a pane learns its own id

Every integration hinges on a shell inside a pane being able to report which pane it is. All three
supported terminals provide this; the id formats differ completely.

| Terminal | Env var | Id format | Round-trips cleanly? |
|---|---|---|---|
| iTerm2 | `$ITERM_SESSION_ID` | `w<W>t<T>p<P>:<UUID>`, e.g. `w1t0p0:D3451194-…` | **no** — see below |
| Kitty | `$KITTY_WINDOW_ID` | bare integer | yes (but the *socket* does not — see below) |
| WezTerm | `$WEZTERM_PANE` | bare integer | yes |
| Ghostty | none | — | — |

Kitty additionally exports `$KITTY_LISTEN_ON` (its control socket) and `$KITTY_PID`.

## iTerm2

**Documented.** Control is via the `iterm2` Python package over a websocket. Activation is
three calls — `app.async_activate()`, `window.async_activate()`, then
`session.async_activate(select_tab=True, order_window_front=True)`. Highlighting builds a
`LocalWriteOnlyProfile` and applies `set_tab_color` / `set_background_color` via
`async_set_profile_properties`. Three push monitors exist: `FocusMonitor`,
`SessionTerminationMonitor`, and `LayoutChangeMonitor`.

**Documented — two user-granted prerequisites.** The "Enable Python API" setting must be on
(Settings → General → Magic), and macOS Automation (Apple Events) permission must be granted,
triggered by the AppleScript cookie request
`tell application "iTerm2" to request cookie and key for app named "Juggler"`.

**Verified — `FocusMonitor` reports a bare UUID, everything else reports the prefixed form.**
Hooks and stored ids carry `w1t0p0:UUID`; focus events carry only the UUID. Ids must be matched
with a suffix comparison, never equality. This has broken focus-sync and terminal-info more than
once — see the post-mortem
[`docs/log/2026-02-01-focus-sync-not-updating-selection.md`](../log/2026-02-01-focus-sync-not-updating-selection.md)
(2026-02-01), where a refactor regressed to `==` and silently disabled focus-sync entirely. It is
called out as a recurring trap in [`AGENTS.md`](../../AGENTS.md).

**Verified — a stale session raises an exception with an empty message.** iTerm2's cached app model
can hand back a `Session` object for a UUID whose tab is already gone; touching `session.tab` or
`tab.window`, or calling `async_activate` on it, raises with `str(e) == ""`. Any error handling that
matches on message text (`"session not found"`) therefore fails to classify it, and the session
never gets cleaned up. Recorded in
[`docs/tech/iterm2-daemon.md`](../tech/iterm2-daemon.md) (2026-07-18).

**Verified — `SessionTerminationMonitor` lags ~5 s.** It fires only once the underlying process
actually exits. `LayoutChangeMonitor` sees the pane disappear immediately, which is why both are
subscribed and the layout diff is what actually drives prompt cleanup.

**Verified — `run_until_complete(retry=True)` never gives up and swallows `SystemExit`.** On
connection-refused or HTTP 401 the `iterm2` library retries forever with no built-in timeout, so an
external watchdog is required (a `SIGALRM` at 30 s around the initial connect). Worse, raising
`SystemExit` from inside an asyncio task under that wrapper is caught and turned into a reconnect —
a daemon that wants to exit must call `os._exit()`.

**Verified — `async_set_profile_properties` can silently no-op.** Against a wedged profile the
highlight simply does not apply. A retry after 1 s helps; for resetting a pane background, injecting
the OSC sequence `\033]1337;SetColors=bg=default\a` directly into the stream succeeds where the
profile API does not.

**Verified — the bundled Python is selected lexicographically, so 3.8 can win.** iTerm2 ships its
own interpreters under `~/Library/Application Support/iTerm2/iterm2env/versions/`. Sorting those
directory names as strings puts `3.8.x` ahead of `3.10.x` and `3.14.x`. A commit that modernized the
daemon's type hints to built-in generics (`dict[str, Any]`) therefore crashed at import with
`TypeError: 'type' object is not subscriptable`, taking down all iTerm2 integration and surfacing
only as stale-connection recovery loops. See
[`docs/log/2026-02-07-daemon-crash-python-type-hints.md`](../log/2026-02-07-daemon-crash-python-type-hints.md)
(2026-02-07). The daemon must stay Python 3.7-compatible.

**Documented — the daemon exists for latency.** Spawning a Python process per command costs
roughly 1000 ms against roughly 50 ms over a persistent connection. This figure is the stated
rationale in [`docs/tech/iterm2-daemon.md`](../tech/iterm2-daemon.md); it is not an instrumented
benchmark in this repo.

## Kitty

**Documented.** Remote control via the `kitten @` CLI. `kitty.conf` must set
`allow_remote_control socket-only` (or `yes`), `listen_on unix:/tmp/kitty-{kitty_pid}`, and a
`watcher` line pointing at a Python watcher script. Kitty must be **restarted** for any of these to
take effect — there is no reload path for them.

**Verified — a GUI-launched process does not inherit `KITTY_LISTEN_ON`, and `kitten @` without
`--to` hangs.** An app launched from the Dock or Finder has no Kitty environment, so every remote
command must pass an explicit `--to unix:<socket>`. Omitting it does not error; it blocks. The
socket has to be found by scanning `/tmp` for `kitty-*` instead, and with more than one candidate
the right one is identified by probing each with `ls` until the target window id appears. Recorded
in [`docs/tech/kitty-integration.md`](../tech/kitty-integration.md) (2026-08-09).

**Verified — `$KITTY_LISTEN_ON` from a remote session points at the remote host.** For an ssh
session the hook-supplied socket is unusable and must be discarded in favour of a locally
discovered one. The id itself is fine; only the transport is wrong.

**Documented — the watcher runs inside Kitty's own process.** Registered via the `watcher` config
directive, it implements Kitty's `on_focus_change(boss, window, data)` and
`on_close(boss, window, data)` callbacks. This is the only push mechanism Kitty offers; there is no
external event stream. Because the callback runs in-process, a watcher that throws takes Kitty with
it — the POST must be fire-and-forget inside a bare `except`.

**Gotcha — watcher pushes have no retry.** A dropped close event leaks a stale session until some
later activation attempt notices the pane is gone.

**Gotcha — two different ids in `ls` output.** The per-pane `"id"` is what `--match` accepts; the
OS window's `"platform_window_id"` is a different number, useful only for display naming.

## WezTerm

**Documented.** Pure CLI. `wezterm cli` locates the running GUI instance itself — no socket
registration, no config, no watcher, no permission prompt. `wezterm cli list --format json` returns
a flat array of pane objects (`window_id`, `tab_id`, `pane_id`, `title`). `wezterm cli
activate-pane --pane-id <id>` focuses a pane, though it may only select within an already-focused
window, so foregrounding the app still needs AppleScript.

**Verified — ids round-trip exactly.** The same integer appears in `$WEZTERM_PANE`, in `pane_id`,
and as the argument to `activate-pane`. No prefix or suffix transform, unlike iTerm2.

**Verified — highlighting is impossible from outside.** WezTerm can only color a tab from inside its
Lua config, driven by a user var set by an OSC escape emitted from within the pane. There is no
`wezterm cli` command to set a user var or a color, and `wezterm cli send-text` writes to the pane's
**stdin** — as if typed — rather than to its output stream, so an external process cannot trigger a
color change at all. Recorded in [`docs/tech/wezterm-bridge.md`](../tech/wezterm-bridge.md)
(2026-07-24).

**Verified — there is no external event stream.** WezTerm's focus and lifecycle events
(`window-focus-changed`, `user-var-changed`, …) are internal Lua window events with nothing to
subscribe to from outside. Focus-sync is therefore unavailable, and a closed pane is only noticed
when a later lookup fails to find it.

**Verified — `list` carries no active-pane flag.** Nothing in the output says which pane is
focused.

**Verified — `tab_id` is not unique across windows.** The same numeric `tab_id` is reused in
different windows, so any grouping must key on `window_id` **and** `tab_id` together or panes from
unrelated windows merge.

**Verified — `wezterm cli` will spawn a mux server if none is running.** Invoking it with no live
instance runs `wezterm-mux-server --daemonize` rather than failing fast. Observed 2026-08-22 against
**wezterm 20240203-110809-5046fc22** by running `wezterm cli list --format json` headless: it
attempted the spawn, then failed to connect. The CLI is not a pure read-only query.

**Gotcha — multi-instance targeting is unresolved.** Auto-location assumes a single running GUI
instance; with several independent instances, activation can target the wrong one. Capturing
`WEZTERM_UNIX_SOCKET` from the pane (mirroring Kitty's approach) is the known fix and is not
implemented.

**Gotcha — the docs moved.** WezTerm's documentation is now served from `wezterm.org`; the older
`wezfurlong.org/wezterm/` deep links 404 (checked 2026-08-22).

## Ghostty

**No automation surface.** Ghostty exposes no CLI, socket, or scripting API, so none of activation,
highlighting, session lookup, or events is possible. There is also **no per-pane environment
variable**, which is the harder blocker: without one, a shell inside a pane cannot report which pane
it is, so an inbound event could never be routed even if a control API appeared later.

Ghostty is recognized here only by bundle identifier (`com.mitchellh.ghostty`) for display purposes.
Upstream tracking: [ghostty-org/ghostty#2353](https://github.com/ghostty-org/ghostty/discussions/2353).

## Cross-terminal gotchas

- **Self-discovery is the fatal capability, not activation.** A terminal with a rich control API but
  no per-pane env var cannot be integrated at all, because inbound events can never be tied to a
  pane. This is what rules out Ghostty, and it is the first thing to check for any new terminal —
  see [`.claude/skills/integrate-terminal`](../../.claude/skills/integrate-terminal/SKILL.md).
- **"Gone" and "couldn't tell" must stay distinguishable.** Every one of these APIs has a failure
  mode that looks like absence: iTerm2's empty-message exception, Kitty's hang without `--to`,
  WezTerm's exit-zero-but-unparseable output. Collapsing those into "the session is gone" evicts
  live sessions.
- **Subprocess pipes deadlock if not drained.** Every CLI-driven path needs concurrent
  stdout/stderr draining plus a hard timeout; a full 16–64 KB kernel pipe buffer blocks the child's
  `write()` and hangs the caller with no error.
- **A `readabilityHandler` at EOF spins forever.** Once the write end closes, the kernel reports the
  fd readable-at-EOF indefinitely and the handler re-fires in a tight loop, pinning a core per dead
  child. It must remove itself on an empty read. Guarded by the idle-CPU harness
  ([`docs/perf/idle-cpu.md`](../perf/idle-cpu.md)).
- **tmux caches the terminal's env var.** A tmux session keeps whatever `$ITERM_SESSION_ID` /
  `$WEZTERM_PANE` it was created with, so the id goes stale when the session is re-attached
  elsewhere. tmux configs need `update-environment` entries for these vars.
- **Over ssh, the local pane id is simply absent.** All three terminals' env vars are local, so a
  remote session cannot be addressed by them and a local `tmux select-pane` would target the wrong
  tmux entirely.

## Upstream

| Terminal | Docs | Notes |
|---|---|---|
| iTerm2 | [Python API](https://iterm2.com/python-api/) | requires "Enable Python API" plus macOS Automation permission |
| Kitty | [remote control](https://sw.kovidgoyal.net/kitty/remote-control/), [watchers](https://sw.kovidgoyal.net/kitty/launch/) | config changes need a restart |
| WezTerm | [wezterm.org](https://wezterm.org/), [`wezterm cli`](https://wezterm.org/cli/cli/) | docs moved off `wezfurlong.org` |
| Ghostty | [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) | [scripting API discussion](https://github.com/ghostty-org/ghostty/discussions/2353) |

Versions present on the maintainer's machine when this file was last revised (2026-08-22):
kitty 0.45.0, WezTerm 20240203-110809-5046fc22. iTerm2 and Ghostty were not installed, so nothing
here carries a fresh verification against them.

---

[← Reference index](overview.md)

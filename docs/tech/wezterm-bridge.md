# WezTerm Bridge

`WezTermBridge` (`Services/WezTermBridge.swift`) integrates WezTerm via the `wezterm cli`
command-line interface. It is the leanest of the three terminal bridges: WezTerm needs no
daemon, no watcher, no config edits, and no per-session socket. For the cross-terminal
protocol and `TerminalActivation` orchestration, see [terminal-bridges.md](terminal-bridges.md).

## Capabilities

| Capability | Mechanism | Status |
|---|---|---|
| Activate a session | `wezterm cli activate-pane --pane-id <N>` | ✅ |
| Addressing (pane self-discovery) | `$WEZTERM_PANE` env var, read by the hook script | ✅ |
| Session info / gone detection | `wezterm cli list --format json` | ✅ |
| Highlight (tab/pane color) | — | **Not available** |
| Focus-sync (follow frontmost pane) | — | **Not available** |

### Why no highlight or focus-sync

WezTerm exposes no external mechanism for either:

- **Highlight.** WezTerm can only color a tab from inside its Lua config, driven by a *user
  var* set by an OSC escape emitted **from within the pane**. There is no `wezterm cli`
  command to set a user var or a color, and `wezterm cli send-text` writes to the pane's
  stdin (as if typed) rather than to its output stream, so an external process cannot trigger
  a color change. `WezTermBridge.highlight(...)` is therefore a no-op.
- **Focus-sync.** WezTerm's focus and lifecycle events (`window-focus-changed`,
  `user-var-changed`, …) are internal Lua window events with no external stream to subscribe
  to. Juggler does not poll, so it cannot follow which pane is frontmost.

A closed pane is still cleaned up: on the next activation attempt `TerminalActivation` calls
`getSessionInfo`, which returns `nil` (confirmed gone), and the stale session is removed.

## Addressing

The hook script (`Resources/hooks/notify.sh` and the per-agent equivalents) detects WezTerm by
the `$WEZTERM_PANE` environment variable — an **integer** pane id set inside every WezTerm
pane — and reports it as the terminal session id with `terminalType = "wezterm"`. The same
integer id is used by `activate-pane`, appears in `$WEZTERM_PANE`, and is the `pane_id` field
of `wezterm cli list`. No prefix/suffix transform is applied — unlike iTerm2's
`w1t0p0:UUID`/bare-UUID split, WezTerm ids match exactly.

Because `wezterm cli` locates the running GUI instance itself, the bridge needs no
`prepareAddressing` step and no socket registration.

## `getSessionInfo` three-valued contract

`getSessionInfo` honors the contract described in [terminal-bridges.md](terminal-bridges.md):

- pane present in `wezterm cli list` → `TerminalSessionInfo`,
- list succeeded but the pane id is absent → `nil` (confirmed gone),
- the command failed (no GUI instance, timeout, non-zero exit, unparseable output) → **throws**.

`isActive` is best-effort `false`: `wezterm cli list` carries no active-pane flag.

## tmux & ssh

- **tmux.** `$WEZTERM_PANE` reflects the outer WezTerm pane hosting tmux, so activation focuses
  that pane; the inner tmux pane is then selected by Juggler's existing `TMUX_PANE` handling.
  The tmux setup forwards `WEZTERM_PANE` via `update-environment` alongside the iTerm2/Kitty
  vars.
- **ssh.** `$WEZTERM_PANE` is a local env var and is not present on a remote host, so a remote
  WezTerm-hosted session is not locally addressable — the same limitation the iTerm2 and Kitty
  bridges have.

## Setup

None required beyond having WezTerm installed and the `wezterm` CLI resolvable — either on a
standard path (`/opt/homebrew/bin`, `/usr/local/bin`, or inside `WezTerm.app`) or anywhere on
the process `PATH`. Both the bridge (`start()`) and the setup/settings UI resolve it through
the same `WezTermBridge.locateCLI()`, so a PATH-only install isn't reported missing. The
Integration Hub's WezTerm card verifies it and flips the `wezTermEnabled` flag; `uninstall.sh`
has nothing to remove.

## Multi-instance caveat

v1 relies on `wezterm cli` auto-locating a single running GUI instance. With multiple
independent WezTerm instances, activation could target the wrong one. If that proves an issue,
a follow-up can capture `WEZTERM_UNIX_SOCKET` from the hook (mirroring Kitty's `kittyListenOn`)
and pass it in the CLI's environment.

---

[← Back to Tech Overview](overview.md)

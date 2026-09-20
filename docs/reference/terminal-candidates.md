# Terminal Candidates

Which terminals beyond the four Juggler already knows (iTerm2, Kitty, WezTerm, Ghostty-as-stub)
could carry the feature set, surveyed against upstream documentation on **2026-09-19**: what each
one exposes for bringing a window/tab/pane to the front, marking it in the tab bar, and telling us
when the user focuses or closes a pane — plus the terminals that cannot, and why.

This is the survey doc. The deep per-terminal facts for the terminals we already integrate live in
[`terminal-control-apis.md`](terminal-control-apis.md) — and this pass found two of that doc's
claims stale: Ghostty grew an AppleScript dictionary in 1.3.0, and WezTerm's CLI can set tab titles
and activate tabs on the version we already pin. Both corrections are folded in there too.

How this was established: every claim below is **Documented** (upstream docs, man page, `--help`
output, or upstream source, linked) unless marked **Verified** (observed on this machine: the tmux
3.6a man page, WezTerm 20240203 `cli --help`, VS Code's source). None of the new candidates except
VS Code is installed here, so none was *driven* — a real integration still starts with the
[`integrate-terminal`](../../.claude/skills/integrate-terminal/SKILL.md) Phase 1 probe, not with
this page.

- [What Juggler needs from a terminal](#what-juggler-needs-from-a-terminal)
- [Matrix](#matrix)
- [Ghostty](#ghostty)
- [Warp](#warp)
- [Otty](#otty)
- [cmux](#cmux)
- [Terminal.app](#terminalapp)
- [WezTerm deltas](#wezterm-deltas)
- [Wave](#wave)
- [Tabby](#tabby)
- [Second sweep: more GUI terminals](#second-sweep-more-gui-terminals)
- [Editors: VS Code family, Zed, JetBrains, Nova, Lapce, CodeEdit](#editors-vs-code-family-zed-jetbrains-nova-lapce-codeedit)
- [Agent-orchestrator apps are not terminals](#agent-orchestrator-apps-are-not-terminals)
- [Fatal or unknown: Alacritty, Hyper, Rio, Contour](#fatal-or-unknown-alacritty-hyper-rio-contour)
- [Multiplexers as a layer: tmux and zellij](#multiplexers-as-a-layer-tmux-and-zellij)
- [Generic fallbacks that work in any terminal](#generic-fallbacks-that-work-in-any-terminal)
- [What this suggests](#what-this-suggests)
- [Upstream](#upstream)

## What Juggler needs from a terminal

Outbound — the [`TerminalBridge`](../tech/terminal-bridges.md) protocol:

| Need | Bridge surface | Notes |
|---|---|---|
| A control mechanism at all | `start` / `stop` | CLI, AppleScript dictionary, socket/RPC, or extension API |
| Activate a pane | `activate(sessionID:)` | window to front **and** the right tab selected **and** the right split pane focused; app-level `activate` alone is not enough |
| Flash a highlight | `highlight(sessionID:tabConfig:paneConfig:)` | tab color and pane background color, then reset after N seconds |
| Still-exists check | `getSessionInfo` | three-valued: info / confirmed-gone (`nil`) / couldn't-tell (throw) — a lookup that can't distinguish those evicts live sessions |
| Per-session transport | `prepareAddressing` | kitty's control socket (`KITTY_LISTEN_ON`); nil for terminals addressed directly by id |

Inbound — what makes the monitor feel alive:

| Need | Path today | Notes |
|---|---|---|
| **Pane self-discovery** | hook payload `terminal.sessionId` | **the fatal one.** A process inside a pane must report a stable pane id (`ITERM_SESSION_ID`, `KITTY_WINDOW_ID`, `WEZTERM_PANE`). The detection itself lives in hooklinesinker, keyed on `TERM_PROGRAM` and friends — a new terminal needs a detection story too |
| Focus events | iTerm2 `FocusMonitor`, kitty watcher → `/kitty-event` | push preferred; poll-able focus state is a weaker substitute |
| Close events | iTerm2 monitors, kitty `on_close` | without them, cleanup falls back to activation-time `getSessionInfo` |
| tmux interplay | `tmuxPane` composite id, `liveHostPaneID`, `tmux select-pane` | ids go stale under tmux and ssh; already handled in `TerminalActivation` |

One axis is currently unused: **nothing sets a tab's title.** The bridges only *read* `tabName`
(for the monitor's terminal-info line). Every candidate below is scored on title-setting too,
because a title marker is the one form of tab-bar highlight that survives in terminals with no
color API — and the user-visible ask ("highlight it in the tab bar") can be met with text where
color is impossible.

## Matrix

| | Self-discovery | Activate existing pane | Set tab title | Tab/pane color | Focus events | Close / still-exists | State |
|---|---|---|---|---|---|---|---|
| [Ghostty](#ghostty) 1.3+ | **gap** (no id env var); cwd-query workaround | `focus` + `select tab` + window front | `perform action set_tab_title:` | gap | gap; poll `front window`, `focused terminal` | query (`every terminal whose …`) | near-complete |
| [Terminal.app](#terminalapp) | **gap**; tty workaround | tab `selected` r/w, window `frontmost` r/w | `custom title` r/w | tab `background color` r/w | gap; poll `selected` | poll (`exists`, `tty`) | partial: no splits, no push |
| [Warp](#warp) | `WARP_TERMINAL_SESSION_UUID` | `open "$WARP_FOCUS_URL"` | OSC only | gap | gap | gap (deep link to a dead pane: unestablished) | partial, brand-new upstream |
| [Otty](#otty) | `$OTTY_PANE_ID` | `otty pane focus` / `otty://pane/<id>` | `otty tab rename` + status badges | gap (badges instead) | gap; poll `otty panes --json` | no-match selector exits 4 | near-complete, very young |
| [cmux](#cmux) | `CMUX_WORKSPACE_ID` + `CMUX_SURFACE_ID` | `focus-panel` + `select-workspace` (window-raise unestablished) | gap (no rename verb) | gap (sidebar status pill instead) | gap; poll `identify --json` | `surface.list` lookup | near-complete; socket needs `allowAll` |
| [WezTerm](#wezterm-deltas) | `$WEZTERM_PANE` | `activate-pane` / `activate-tab` | `set-tab-title` | gap (config-only) | `window-focus-changed` Lua (config cooperation) | `list` lookup | ours; corrections below |
| [Wave](#wave) | `WAVETERM_BLOCKID` | **gap** (no focus verb in `wsh`) | not established | `wsh setbg` (tab color) | gap | `blocks list` | partial |
| [Tabby](#tabby) | **gap** | plugin only | plugin only | plugin only | plugin only | plugin only | plugin-only path; active |
| [Alacritty](#fatal-or-unknown-alacritty-hyper-rio-contour) | `ALACRITTY_WINDOW_ID` | **gap** (create-window only) | OSC | gap | gap | gap | fatal: no activation |
| Rio, Contour | not found | not found | — | — | — | — | unknown; active projects |
| Hyper | — | — | — | — | — | — | dead since 2023 |
| [VS Code](#editors-vs-code-cursor-windsurf-zed-jetbrains) | **gap** (no instance env var); pid/tty correlation | `Terminal.show()` switches the panel; no window-raise API | not established | gap | `onDidChangeActiveTerminal` + `onDidChangeWindowState` (push, via extension) | `onDidCloseTerminal` (push, via extension) | full-featured via a shipped extension |
| Zed | — | — | — | — | — | — | fatal: no terminal API |
| JetBrains | **gap** | plugin only | plugin only | plugin only | plugin only | plugin only | plugin-only; not evaluated |
| [tmux](#multiplexers-as-a-layer-tmux-and-zellij) | `$TMUX_PANE` | `select-pane` / `select-window` — in-terminal only | `rename-window` | gap | **push hooks** `pane-focus-in` / `client-focus-in` | `list-panes`, `pane-exited` hook | universal layer, any host terminal |
| [zellij](#multiplexers-as-a-layer-tmux-and-zellij) | `$ZELLIJ_PANE_ID` | `focus-pane-id` — in-terminal only | `rename-tab-by-id` | **`set-pane-color --bg`** | gap; poll `list-panes --json` `is_focused` | `list-panes` (`exited`, `exit_status`) | universal layer, best control |

iTerm2 and Kitty are absent from this matrix on purpose — they are the ceiling, covered in
[`terminal-control-apis.md`](terminal-control-apis.md). X11/Wayland-only emulators (foot, urxvt, st,
…) are out of scope for a macOS app. GNU Screen was not evaluated; tmux and zellij cover the
multiplexer role.

## Ghostty

**Documented — 1.3.0 (tagged 2026-03-09; 1.3.1 is current) added a full AppleScript dictionary.**
"Ghostty on macOS exposes a native AppleScript dictionary so scripts can query and control terminal
windows, tabs, and split panes" ([features/applescript](https://ghostty.org/docs/features/applescript)).
The object model is `application -> windows -> tabs -> terminals`, where a *terminal* is a split
pane. What matters to Juggler:

- **Activation**: "`focus` | Focus a terminal and bring its window to front", plus `select tab` and
  `activate window` — the whole window/tab/pane triple in one call.
- **Tab title**: "Use `perform action` with `set_tab_title` to label tabs from a script."
- **Queries**: whose-clauses over the tree, e.g. `every terminal whose working directory contains
  "ghostty"`, and `working directory` / `name` / `id` / `index` / `selected` on every object —
  enough to implement `getSessionInfo`.
- **Default on**: "AppleScript support is enabled by default on macOS"; `macos-applescript = false`
  disables it. First use triggers the usual TCC Automation prompt.

**Documented — the self-discovery gap remains.** The child environment, checked against
`src/termio/Exec.zig` at tag `v1.3.1`, sets `GHOSTTY_RESOURCES_DIR`, `GHOSTTY_BIN_DIR`,
`TERM=xterm-ghostty`, `COLORTERM=truecolor`, `TERM_PROGRAM=ghostty`, `TERM_PROGRAM_VERSION` and
`GHOSTTY_SHELL_FEATURES` — still no per-surface id. A hook inside a pane cannot name its pane
directly. The workarounds are real but weaker: match `every terminal whose working directory
contains <cwd>` against the hook's `session.cwd`, or tty-based addressing (below). Both are
ambiguous when two panes share a cwd — Juggler's own `docs/log/` history says ambiguous matching
is where focus-sync bugs come from.

**Documented — no events, no colors.** Nothing pushes focus or close changes; focus state is
poll-able (`frontmost`, `front window`, `selected tab`, `focused terminal`). The keybind-action
surface exposed to `perform action` covers titles and layout, not per-surface colors — so the
color highlight stays a gap; a title marker would not.

## Warp

**Documented — Warp merged exactly Juggler's activation mechanism in May 2026.** PR
[warpdotdev/warp#11130](https://github.com/warpdotdev/warp/pull/11130) ("Expose terminal focus URL
env vars", merged 2026-05-22, closing issue #8611) adds two env vars to every pane:

- `WARP_TERMINAL_SESSION_UUID` — "the terminal session UUID as 32 lowercase hex characters."
- `WARP_FOCUS_URL` — "a channel-aware deep link such as `warposs://session/<uuid>` or
  `warp://session/<uuid>`."

"Opening that URL lets Warp resolve the current window, pane group, and pane internally via the
existing session deep-link handler", and the PR's manual test "verified `open "$WARP_FOCUS_URL"`
focuses the originating pane across multiple panes/windows." That is addressing *plus* activation —
the two capabilities Juggler calls fatal — arriving by env var, the same shape as
`KITTY_WINDOW_ID` + `kitten @ focus-window`. hooklinesinker would need to read the two vars; the
mechanism lives in `crates/warp_terminal/src/focus_env.rs` in the open-source client.

**Documented — everything else is closed.** The [`warp://` scheme](https://docs.warp.dev/terminal/more-features/uri-scheme)
only creates: `warp://action/new_window`, `new_tab`, `launch`, `tab_config`, `settings` deep links.
No focus/close events, no external color or title API (OSC title sequences work from inside the
pane), and the behavior of `WARP_FOCUS_URL` when the pane is already closed is not documented —
gone-detection would stay activation-time.

**Documented — Warp already monitors agents itself.** Its multi-agent guide describes vertical
tabs with "a status indicator showing whether the agent is active, waiting for input, or idle",
notifications "when an agent needs your attention", and an Agent Management Panel that is "a
dashboard view of what's running, what's waiting, and what's finished"
([guide](https://docs.warp.dev/guides/agent-workflows/how-to-run-multiple-ai-coding-agents)).
`TERM_PROGRAM` is set to `WarpTerminal` (from `crates/warp_terminal/src/local_tty/unix.rs`). For
Juggler the pitch is narrower than for other terminals: activation for users who run agents in
Warp but don't live in Warp's own dashboard.

Caveats: the env vars shipped after 2026-05-22 — dev releases from June 2026 carry them, but
which *stable* release first included them was not established from here.

## Otty

**Documented — a 2026 macOS terminal whose CLI covers nearly the whole contract.** Otty
([otty.sh](https://otty.sh), [otty-shell/otty](https://github.com/otty-shell/otty)) ships an `otty`
CLI plus an `otty://` URL scheme plus a Terminal.app-compatible AppleScript dictionary:

- **Addressing**: "the `$OTTY_PANE_ID` variable Otty exports into every pane", with
  `otty panes --json` to enumerate.
- **Activation**: window/tab/pane subcommands — "Common subcommands across the three: `show`,
  `list`, `new`, `close`, `focus`, `rename`" — and deep links: "`open otty://pane/$OTTY_PANE_ID` —
  focus the pane this shell is running in."
- **Tab title and more**: `otty tab rename`, and `otty tab badge --kind …` with "Badge kinds are
  `running`, `completed`, `finished`, `unread`, `error`, `awaiting-input`."
- **Clean absence**: "a non-matching selector fails with `No pane/tab matched selector` (exit 4)
  rather than falling back to the active one" — a better three-valued contract than most.
- **Guards**: `do script`/capture are refused on SSH and `sudo` panes unless the user opts in.

**Documented — it also tracks coding agents natively.** "`otty state:<agent> key=value …` reports
a code-agent's lifecycle state", invoked by Otty's bundled agent hooks, and "`otty watch:claude
<id>` … blocks until the named code-agent session reaches the *idle* state"
([CLI reference](https://docs.otty.sh/reference/cli)). Otty is doing the inbound half of Juggler's
job inside the terminal itself — an integration would overlap its own feature set, which cuts both
ways.

**Gotchas.** No focus/close push events (poll `otty panes --json`); no per-pane color control
documented (badges are the highlight); focus sync would be polling. And the project launched in
2026 and is moving fast — repo last pushed 2026-09-03, 344 stars, **no license detected by
GitHub**, GitHub releases stalled at v0.1.0 (2026-03-11) while the docs reference 1.2.0/1.3.0
features. Building on it now means tracking a fast-moving target with unclear licensing.

## Terminal.app

**Documented — the dictionary is stronger than its reputation.** From a published mirror of the
macOS 15.6 `Terminal.sdef` ([applescript-hub](https://github.com/svd-ai-lab/applescript-hub/blob/main/app-dictionaries/terminal.md);
the bundle's own sdef is not readable from this sandbox):

- `tab` properties include `custom title` (**r/w**), `background color` (**r/w**), `cursor color`
  (r/w), `selected` (**r/w**), `tty` (r/o), `busy`, `processes`, `contents`, `history`,
  `current settings` (r/w).
- `window` properties include `id` (r/o) and `frontmost` (**r/w** — setting it brings that window
  to front).
- `do script … in <tab>` returns the tab it ran in; `settings set` also carries `background color`.

So: activation (window `frontmost` + tab `selected`), tab title (`custom title`), and a real
color highlight (`background color` per tab) are all in the dictionary. Terminal-compatible
references corroborate the behavior: "set selected of tab 3 of window 1 to true — Bring a
background tab forward" ([Otty's Terminal-compat notes](https://docs.otty.sh/reference/applescript)).

**Documented — the gaps.** No split panes: the dictionary has no pane/split class, and macOS 26
Tahoe's Terminal changes are visual ("supports 24-bit color and Powerline fonts, and adopts the new
Liquid Glass aesthetic" — [MacRumors](https://www.macrumors.com/2025/09/24/all-the-new-macos-tahoe-features/)).
No events: focus is poll-only (`selected` of tabs, `frontmost`), close is poll-only (`exists`,
`tty` gone). No per-tab env var: `TERM_PROGRAM=Apple_Terminal` is all a pane sees, so addressing
must go through `tty` — the hook reports its tty, Juggler matches it against `tty` of `every tab`
(see [fallbacks](#generic-fallbacks-that-work-in-any-terminal); needs a hooklinesinker payload
change). macOS Sequoia+ may also require per-scripting Automation (Apple Events) grants.

**Gotcha — not probed.** The r/w flags are the dictionary's promise, not an observed behavior;
driving Terminal.app from this session would have launched a GUI app on the user's desktop. The
`selected tab of window` shorthand appears in Terminal-compatible docs but was absent from the
sdef mirror we checked — verify with a probe before relying on it.

## WezTerm deltas

Facts that [`terminal-control-apis.md`](terminal-control-apis.md) recorded conservatively, all
**Verified** against the installed 20240203-110809-5046fc22 binary on 2026-09-19:

- `wezterm cli set-tab-title <title> --tab-id <id>` exists ("Change the title of a tab") — so the
  **tab-bar title** axis works on WezTerm today, on the version we pin. Color remains config-only.
- `wezterm cli activate-tab --tab-id <id>` exists ("Activate a tab"), alongside `activate-pane`.
- No stable release since 20240203 (checked 2026-09-19); newer features ride the nightly channel.
  Nothing newer than 20240203 is required for the above.
- `$WEZTERM_UNIX_SOCKET` is documented instance-targeting
  ([cli docs](https://wezterm.org/cli/cli/)) — the known fix for the multi-instance gotcha in the
  main doc, still unimplemented in our bridge.
- The Lua event `window-focus-changed` has existed "Since: Version 20221119-145034-49b9839f"
  ([docs](https://wezterm.org/config/lua/window-events/window-focus-changed.html)), with
  `window:is_focused()` available. A user's `wezterm.lua` can shell out on focus change and POST to
  Juggler — the same cooperation class as kitty's watcher. Focus-sync is therefore *config-
  cooperative*, not impossible.

## Wave

**Documented — block-level addressing and a color highlight, but no focus.** Wave
([waveterm.dev](https://www.waveterm.dev/), v0.14.5 2026-04-16, active) injects
`TERM_PROGRAM=waveterm`, `WAVETERM_BLOCKID` ("the id of the block containing your current terminal
widget"), `WAVETERM_TABID`, `WAVETERM_WORKSPACEID`, `WAVETERM_CLIENTID` into terminal sessions
([connections docs](https://docs.waveterm.dev/connections)). Its `wsh` CLI queries
(`wsh blocks list --json`, filterable by window/tab/view; `wsh getmeta -b <blockid>`) and can
color a tab: "The `setbg` command allows you to set a background image or color for the current
tab", hex or CSS color, with `--opacity` ([wsh reference](https://docs.waveterm.dev/wsh-reference)).
But the `wsh` verb list has no focus/activate command — nothing brings a block, tab, or window to
the front — and no event stream. Without activation the integration is dead regardless of the rest.

## Tabby

**Documented — active, but everything goes through a plugin.** Tabby (v1.0.235, 2026-07-22) is an
Electron terminal with a real plugin API — the `tabby-terminal` package documents services for
"terminal tabs, terminal frontends, session management" including a `MultifocusService`
([docs.tabby.sh](https://docs.tabby.sh/terminal)). A sufficiently motivated plugin could do all of
activation, titles, colors, and focus events, because it runs inside the app. But there is no
documented CLI control of a running instance, and no per-pane env var a hook could report —
addressing would have to be invented inside the plugin (e.g. injecting one). That is the heaviest
setup burden of any live candidate: ship and maintain a Tabby plugin, and the user installs it.

## Editors: VS Code, Cursor, Windsurf, Zed, JetBrains

Agent sessions increasingly run in editor terminals, and none of them behave like a standalone
terminal.

**VS Code — full-featured, but only through a shipped extension.** From the
[extension API reference](https://code.visualstudio.com/api/references/vscode-api):
`window.terminals` ("The currently opened terminals or an empty array"),
`onDidChangeActiveTerminal: Event<Terminal | undefined>`, `onDidOpenTerminal` /
`onDidCloseTerminal`, `onDidChangeWindowState` with `focused`, `Terminal.show(preserveFocus?)`,
`Terminal.processId: Thenable<number>`, `Terminal.state`, `Terminal.creationOptions`. So an
extension can push focus changes (active terminal + window focused) and close events to Juggler's
HTTP sink, and reveal a terminal in the panel. Three hard limits, all negative-evidence findings
against that reference page: there is **no terminal-tab API** (zero occurrences of `TerminalTab`),
**no API to raise/activate the editor window itself** — activation stops at the panel — and
**no env var identifies the terminal instance**: the shell sees `TERM_PROGRAM=vscode` etc.
(set in `terminalEnvironment.ts`: `env['TERM_PROGRAM'] = 'vscode'`), so a hook's `terminal.sessionId`
has nothing to match; correlation would go through `Terminal.processId` (the shell pid) against the
pid ancestry of the hook process — a new addressing path, not an env var. Setup burden is a new
artifact class for Juggler: a VSIX the user installs (the Pi-extension installer is the in-repo
precedent). Cursor and Windsurf are VS Code forks shipping the same extension API — reported, not
independently verified here.

**Zed — nothing today.** The extension capability list is "Language Extensions, Debugger
Extensions, Theme Extensions, Icon Theme Extensions, Snippets Extensions, MCP Server Extensions,
Agent Server Extensions" ([docs](https://zed.dev/docs/extensions)) — no terminal panel API, and
community roadmap threads in 2026 still rank the extension API low. Until that changes there is no
path.

**JetBrains — plugin-possible, not evaluated.** The IntelliJ platform exposes terminal control to
plugins (community threads show plugins creating terminal tabs), but even keyboard focus of a
specific terminal tab is awkward enough to spawn support threads (2026). Same shape as Tabby:
everything via a heavy plugin; we did not assess it further.

## Fatal or unknown: Alacritty, Hyper, Rio, Contour

**Alacritty — fatal.** v0.17.0 (2026-04-06), and `alacritty msg` is exactly three messages:
`create-window`, `config`, `get-config` ([man page](https://alacritty.org/cmd-alacritty-msg.html)).
It can *create* windows and restyle them (`--window-id`, defaulting to `$ALACRITTY_WINDOW_ID`),
but cannot focus, raise, or select an existing one — and Alacritty has no tabs and no splits, so
there is no tab bar or pane to target anyway. Addressing exists; activation does not. Dead end
for our feature set.

**Hyper — dead.** Last stable release v3.4.1 on 2023-01-08, canaries ended mid-2023. Its Electron
plugin API is irrelevant if the project is unmaintained; a Juggler integration would inherit the
abandonment.

**Rio — unknown, active.** v0.5.28 shipped 2026-09-17; splits exist ("Demo with split and CRT on
MacOS" in the README). No CLI-control surface, IPC, or per-pane env var surfaced in the README or
a docs pass (`rioterm.com/docs` root did not resolve through the fetcher). Not evaluated deeper;
treat as unknown rather than absent.

**Contour — unknown.** 0.7.0.8982 (2026-08-17), active, but no control surface or identity env
var found in a quick pass. Same treatment.

## Multiplexers as a layer: tmux and zellij

A multiplexer can give any host terminal the control and event surface it lacks — except raising
the host terminal's OS window, which only the host (or AppleScript app-activate) can do. Juggler
already models this half-way: `tmuxPane` is part of session identity and activation runs
`tmux select-pane`.

**tmux — the event layer. Verified against the installed 3.6a man page:**

- Hooks: "`pane-focus-in` — Run when the focus enters a pane, if the `focus-events` option is on"
  (and `pane-focus-out`); "`client-focus-in` — Run when focus enters a client" (and
  `client-focus-out`); `pane-exited`, `session-closed`, `client-detached`, `client-session-changed`
  also exist. Hooks run arbitrary commands, so a `run-shell` hook can POST to Juggler's sink.
- The gate: "`focus-events [on | off]` — When enabled, focus events are requested from the
  terminal if supported and passed through to applications running in tmux. Attached clients
  should be detached and attached again after changing this option." The host terminal must
  support DEC 1004 focus reporting (kitty, iTerm2, WezTerm, and Ghostty do).
- Control: `select-pane -t`, `select-window -t`, `rename-window` — in-terminal only.
- Addressing: `$TMUX_PANE` (`%N`), already consumed by our hooks; `list-panes -a` with
  `pane_tty`/`pane_pid` formats for still-exists checks.

So "any terminal + tmux" yields focus **push** events and close events for every session inside
tmux, whatever the host terminal is — the one back-channel that does not care about the host.
iTerm2's tmux control mode (`tmux -CC`) goes further and turns tmux windows into native iTerm2
windows, where our existing bridge already works.

**zellij — the control layer. Documented (v0.45.1, 2026-08-28):** `ZELLIJ_PANE_ID` is exported to
every pane ("The ID of terminal panes is the same one that can be discovered through the
`ZELLIJ_PANE_ID` environment variable"); `zellij action focus-pane-id terminal_1`, `go-to-tab-by-id`,
`rename-tab-by-id`, `close-pane --pane-id` cover control; `list-panes --json` returns `is_focused`,
`title`, `exited`, `exit_status`, `pane_cwd`, `pane_command`, `tab_id` — a richer state query than
tmux's; and uniquely among everything surveyed, **`set-pane-color --pane-id <id> --bg <hex>
--reset`** sets and resets a pane's background color — Juggler's pane-highlight feature, already
built into the multiplexer. No push events were found (focus is poll-only via `list-panes`;
plugins receive events and could pipe them out, but that path was not verified).

## Generic fallbacks that work in any terminal

Three mechanisms are terminal-independent, and one tempting one is a trap:

- **TTY addressing.** Every pane is one pty; a process inside a pane can learn its own tty, and
  any control API that enumerates panes with their tty (Terminal.app's `tty` property; tmux's
  `pane_tty`) can be matched against it. This is the addressing answer for terminals with no id
  env var — but today's hooklinesinker payload carries no tty, so this needs a hooklinesinker
  change (it is ours to change). The tty is also immune to the tmux-cached-id staleness problem.
- **OSC title marking from inside the pane.** Hooklinesinker's hooks run *inside* the pane, and
  every terminal here honors OSC 0/2 title sequences. A state marker written to the tab title at
  each event would work everywhere — including terminals with no control API at all. Caveats:
  shells with title-precmd integration overwrite it, and it is text, never color.
- **AppleScript / Accessibility focus polling.** macOS exposes app activation
  (`NSWorkspace`) and per-app focused-window changes (AX notifications) to any app. Combined with
  title matching, this could approximate focus-sync for terminals with no event surface.
  Title-matching is exactly the fragile kind of correlation this repo's post-mortems warn about;
  treat as last resort. Not probed in this pass.
- **Gotcha — DEC 1004 focus reporting cannot be harvested by a helper.** Terminals that support
  focus reporting send `CSI I` / `CSI O` to the application *in the pane* — they arrive as tty
  **input**, delivered to the foreground process group. A background watcher process cannot read
  them (it gets SIGTTIN), and writing the enable-sequence from a background process would corrupt
  the foreground app's input. Only a process that owns the tty as the foreground app — a
  multiplexer like tmux — can consume them. This is why tmux can offer focus hooks and a naive
  in-pane daemon cannot; don't re-derive it.

## What this suggests

Ordered by capability-per-effort, not by market share:

1. **WezTerm cheap wins now**: `set-tab-title` as the highlight where color is impossible, and a
   documented `window-focus-changed` Lua snippet users can paste for focus-sync — same setup
   burden class as kitty's watcher. No new terminal, no HLS change.
2. **Ghostty Phase 1 re-run**: the "no automation surface" verdict is dead; the open question is
   addressing — cwd-query via AppleScript vs. tty. The `integrate-terminal` capability matrix
   should be re-filled against an installed 1.3.1 before any bridge work.
3. **tmux focus hooks as a cross-terminal back channel**: `pane-focus-in`/`client-focus-in` +
   `run-shell` POSTs give focus-sync in *every* host terminal for tmux users, extending the tmux
   support that already exists.
4. **Warp activation**: `WARP_FOCUS_URL` + `WARP_TERMINAL_SESSION_UUID` are upstream-built for
   exactly this; the work is HLS reading two env vars and a bridge that shells out to `open`.
   No focus events, so the monitor's focus-sync stays absent there.
5. **Otty, Terminal.app**: both would work (Otty nearly completely, Terminal.app minus events and
   splits), but each carries a cost — Otty's age/licensing and built-in overlap, Terminal.app's
   tty-addressing prerequisite and no-splits ceiling.
6. **Not worth pursuing**: Alacritty (no activation of existing windows), Hyper (dead), Zed (no
   API), Wave (no activation), Tabby/JetBrains (plugin-only). Rio and Contour stay open questions.

## Upstream

| Terminal | Docs | Notes |
|---|---|---|
| Ghostty | [AppleScript](https://ghostty.org/docs/features/applescript), [repo](https://github.com/ghostty-org/ghostty) | 1.3.0 tagged 2026-03-09; 1.3.1 current at survey |
| Warp | [URI scheme](https://docs.warp.dev/terminal/more-features/uri-scheme), [multi-agent guide](https://docs.warp.dev/guides/agent-workflows/how-to-run-multiple-ai-coding-agents), [#11130](https://github.com/warpdotdev/warp/pull/11130) | focus env vars merged 2026-05-22; open-source client |
| Otty | [CLI reference](https://docs.otty.sh/reference/cli), [AppleScript](https://docs.otty.sh/reference/applescript), [repo](https://github.com/otty-shell/otty) | no license detected; macOS-only |
| Terminal.app | [sdef mirror](https://github.com/svd-ai-lab/applescript-hub/blob/main/app-dictionaries/terminal.md) | mirror of the macOS 15.6 dictionary |
| WezTerm | [`wezterm cli`](https://wezterm.org/cli/cli/), [window-focus-changed](https://wezterm.org/config/lua/window-events/window-focus-changed.html) | stable frozen at 20240203 |
| Wave | [wsh](https://docs.waveterm.dev/wsh-reference), [env vars](https://docs.waveterm.dev/connections) | |
| Tabby | [terminal plugin API](https://docs.tabby.sh/terminal) | |
| Alacritty | [alacritty-msg(1)](https://alacritty.org/cmd-alacritty-msg.html) | |
| tmux | local man page (3.6a), [site](https://tmux.github.io/) | hooks verified locally |
| zellij | [cli-actions](https://zellij.dev/documentation/cli-actions) | v0.45.1 |
| VS Code | [extension API](https://code.visualstudio.com/api/references/vscode-api) | 1.137.0 installed |
| Zed | [extensions](https://zed.dev/docs/extensions) | |

Versions current as of 2026-09-19: Ghostty 1.3.1, Alacritty 0.17.0, Warp dev v0.2026.06.09+,
Otty ≥1.3.0 (docs), WezTerm 20240203 (stable), Wave 0.14.5, Tabby 1.0.235, Hyper 3.4.1 (2023),
Rio 0.5.28, Contour 0.7.0.8982, tmux 3.6a (installed), zellij 0.45.1, VS Code 1.137.0 (installed).
iTerm2, Kitty, Ghostty, Warp, Otty, Wave, Tabby, Rio, Contour, zellij were not installed on this
machine at survey time.

---

[← Reference index](overview.md)

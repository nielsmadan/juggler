---
name: integrate-terminal
description: Methodical workflow for adding a new terminal integration (a TerminalBridge) to Juggler. Use when adding support for a new terminal emulator — e.g. "integrate WezTerm", "add support for Ghostty", "build a terminal bridge", "let Juggler activate sessions in Foo terminal". Runs an up-front control-API capability check so integration gaps surface before any code is written.
---

# Integrate Terminal

## Overview

Juggler drives terminals *outbound*: given a session it must bring the right window/tab/pane to the foreground, optionally flash a highlight color, and look up whether the session still exists. Each terminal hides these behind a `TerminalBridge`. Adding a terminal means building that bridge plus the addressing path that ties an inbound hook to a real pane, a `TerminalType` case, registration, setup UI, and docs.

**Why this skill exists:** terminal integration fails on a different axis than agent integration. An agent integration can fail because the agent fires no useful *events* (inbound). A terminal integration fails because the terminal exposes no way to *control it* (outbound) — or, more subtly, no way for a pane to learn its own id, so an inbound hook can never be routed to a pane. That last gap is invisible until activation is wired up and nothing focuses. This skill front-loads a control-API capability check so those gaps are surfaced and signed off **before** design and code.

This is the terminal-side sibling of the `integrate-coding-agent` skill. Same shape (capability matrix → Go/No-Go → design → implement → verify), different critical question: not "what events does it fire?" but "what can Juggler make it do, and how does it address a session?"

Do the phases in order. **Do not skip Phase 1, and do not start Phase 2 until the user has signed off on the capability matrix.**

## Phase 1: Control-API Capability Check (MANDATORY — before any design or code)

Research the terminal from its official documentation. Prefer reading the actual docs (CLI reference, AppleScript dictionary, scripting/automation API) over assumptions — if the docs are ambiguous or missing, say so explicitly rather than guessing. Produce the capability matrix in 1e and get sign-off in 1f.

### 1a. Control mechanism

- How is the terminal controlled programmatically at all? If there is **no** automation surface → stop; a bridge is not possible.
- Which of these does it expose (one is enough for basic activation): a **CLI** (like kitty's `kitten @` or WezTerm's `wezterm cli`), an **AppleScript** dictionary, a **socket / RPC daemon** (like iTerm2's Python API), or a config-driven mechanism.
- Does control require a background server/mux to be running (WezTerm mux, iTerm2 Python API)? Does it require the user to enable anything (iTerm2: "Enable Python API")?
- Minimum terminal version that supports the mechanism; whether it is stable or experimental. Note the doc date.

### 1b. Addressing & identity — the critical part

This is where terminal integrations quietly die. Answer each explicitly — a "no" is a finding, not a footnote:

- **Stable session id.** Is there a stable identifier for a pane/tab/window that survives across the terminal's own API calls (kitty window id, iTerm2 `w1t0p0:UUID`, WezTerm pane id)? What is its exact format?
- **Self-discovery from inside a pane — the fatal one.** Can the shell running *inside* a pane learn its own id, via an environment variable (`ITERM_SESSION_ID`, `KITTY_WINDOW_ID`, `WEZTERM_PANE`) or a command? Juggler's hook script runs inside the pane and must report an id that `activate` can later resolve. **No self-discovery path = no way to route a hook to a pane = the terminal cannot be meaningfully integrated.** Treat this as a hard GAP.
- **Id round-trip.** Does the id the pane reports match the id the control API accepts for activation? Beware transforms: iTerm2's FocusMonitor emits a *bare* UUID while sessions are keyed `w1t0p0:UUID` — Juggler matches with `hasSuffix`, never `==` (see the recurring trap in AGENTS.md). Note any prefix/suffix mismatch now.
- **Control socket per session.** Does an inbound event carry a per-session control socket the bridge must remember to reach that session later (kitty's `KITTY_LISTEN_ON`)? If so it flows through `HookAddressingContext` / `prepareAddressing`. Terminals that address directly by id (iTerm2) don't need this.

### 1c. Capability inventory — what Juggler can make it do

For each `TerminalBridge` method, name the mechanism or write **GAP**:

- **activate** — focus a specific window/tab/pane by id. Required; a GAP here kills the integration.
- **getSessionInfo** — query whether a session exists and its tab/window/pane indices. Must support the **three-valued** contract: present → info, confirmed gone → `nil`, couldn't determine → throw. A terminal that can't distinguish "gone" from "lookup failed" makes gone-session cleanup unreliable (see `terminal-bridges.md`).
- **highlight** — set a tab and/or pane background color programmatically, then reset it after N seconds. GAP is acceptable — the highlight feature is simply unavailable (state that plainly). Note if it needs Lua/config cooperation (e.g. WezTerm user-vars + config) rather than a direct CLI.

### 1d. Inbound events (optional)

- **Focus changes.** Does the terminal report when the frontmost pane changes, so Juggler's list can follow focus (iTerm2 FocusMonitor, kitty watcher via `/kitty-event`)? GAP is fine — focus-sync is just unavailable.
- **Session/window close.** Does it report when a pane closes, so Juggler can remove the session? If not, removal falls back to activation-time cleanup (`getSessionInfo` returning `nil` → `TerminalActivation` removes the stale session).
- Delivery path: a watcher process posting to `HookServer`, a shell hook, or none.

### 1e. Transport & lifecycle

- What must `start()` boot (a daemon, a socket connection, a watcher) and `stop()` tear down? Which reference bridge does this resemble — `KittyBridge` (spawns CLI processes, largely stateless) or `ITerm2Bridge` (persistent Python daemon over a Unix socket)?
- Timeouts the API imposes; whether calls block.
- **tmux / ssh.** How does the id behave under tmux, and over ssh? A remote tmux session caches a stale id in its env; Juggler learns the live local pane separately (`liveHostPaneID`) and skips local `tmux select-pane` for remote sessions. Note whether the terminal's id survives tmux/ssh at all.

### 1f. Capability matrix & Go / No-Go checkpoint

Present this matrix and **every GAP** to the user:

| Juggler need | Terminal mechanism | Notes |
|---|---|---|
| activate (focus by id) | ? | GAP here = stop |
| addressing: pane self-discovers id | ? | **fatal GAP if absent** |
| getSessionInfo (3-valued) | ? | needed for gone-session cleanup |
| highlight (tab/pane color) | ? | GAP = feature unavailable |
| inbound focus events | ? | GAP = no focus-sync |
| inbound session-close | ? | GAP → activation-time cleanup |
| tmux / ssh id survival | ? | note quirks |

Also record: control mechanism, id format + self-discovery variable, min version, server/enablement prerequisites, transport model, closest reference bridge.

State plainly what Juggler will and will not be able to do — e.g. "activation works via `wezterm cli activate-pane`; highlight needs Lua config so it's out of scope for v1; no focus-sync." Get explicit user sign-off before continuing. **This checkpoint is the whole point of the skill — do not skip it.** A fatal GAP (no activation, or no pane self-discovery) means the integration should not proceed.

## Phase 2: Design

After sign-off, write a short design doc under `docs/superpowers/specs/` (or follow the user's preference). Decide:

- The `TerminalType` case name and `bundleIdentifier`.
- **A visually distinct `iconName`.** The icon renders next to the other terminals in the session monitor, so it must **not** reuse an existing terminal's SF Symbol — don't default to `apple.terminal.fill` (iTerm2/Ghostty already use it). Prefer a brand-evocative symbol; when nothing thematic fits, a letter-in-a-square (`w.square.fill` for WezTerm, etc.) is monochrome, tint-following, and distinct. The terminal's real color logo is usually the wrong choice — it clashes with the monochrome symbols around it.
- Transport model and which reference bridge to mirror.
- **Which capabilities are in scope** — implement only what the matrix supports. An out-of-scope highlight or focus-sync is a documented non-feature, not a stub that pretends to work.
- The addressing path: direct-by-id, or control-socket via `prepareAddressing` / `HookAddressingContext`.
- How the pane's id reaches Juggler (which env var the hook/notify path reads).

The existing bridges are the reference — read them before designing:
- **`KittyBridge.swift`** — CLI-driven (`kitten @`), control socket per session (`KITTY_LISTEN_ON`), watcher process for inbound events (`juggler_watcher.py` → `/kitty-event`). Mirror this for CLI terminals.
- **`ITerm2Bridge.swift`** — persistent Python daemon (`iterm2_daemon.py`) over a Unix socket, direct addressing by `w1t0p0:UUID`, FocusMonitor for inbound focus. Mirror this for socket/RPC terminals.

## Phase 3: Implementation

Mirror the closest existing bridge. The full file set:

| File | Change |
|---|---|
| `Juggler/Services/<Foo>Bridge.swift` | New `actor <Foo>Bridge: TerminalBridge` implementing all five methods (`start`, `stop`, `activate`, `highlight`, `getSessionInfo`) plus `prepareAddressing` if the terminal uses a per-session control socket. Clone `KittyBridge` (CLI) or `ITerm2Bridge` (daemon). |
| `Juggler/Models/TerminalType.swift` | Add the `.foo` case with `displayName`, `bundleIdentifier`, and a **distinct** `iconName` (see Phase 2 — not a symbol any other terminal already uses). Use the same symbol for the terminal's `IntegrationCard` in `IntegrationHubView`. Update `TerminalTypeTests` to assert the icon. |
| `Juggler/JugglerApp.swift` | Register at init: `await TerminalBridgeRegistry.shared.register(<Foo>Bridge.shared, for: .foo)`. |
| Inbound wiring (if any) | Watcher/hook that posts focus/close events — a bundled script in `Juggler/Resources/` + an installer, and (if a new event shape) a `HookServer` endpoint. Skip entirely if the matrix marked inbound events GAP. |
| Addressing | If the pane id arrives via the standard `/hook` path, ensure the notify script reads the right env var. If a control socket is involved, implement `prepareAddressing` and route `HookAddressingContext`. |
| `Juggler/Views/IntegrationHubView.swift` | Add an `IntegrationCard` + setup view (mirror the Kitty setup flow if a watcher/config step is needed; simpler if activation is zero-setup). |
| Setup controller / `SettingsView.swift` | If setup has steps (installing a watcher, enabling an API), add a controller and a settings `Section`. |
| `Juggler/Resources/hooks/uninstall.sh` | Add a cleanup block for anything installed (watcher, config edits). |
| Tests | `BundleResourcesTests` (any new bundled script is present), a `<Foo>BridgeTests` for id parsing / command construction, and `HookServerTests` if a new endpoint was added. |
| Docs | New `docs/tech/<foo>-bridge.md`; update `docs/tech/terminal-bridges.md` (Supported Terminals table + any quirk), `docs/tech/overview.md`, `docs/overview.md`, `CLAUDE.md`/`AGENTS.md`, `README.md`, `site/index.html`. Then sweep for **every place that enumerates the supported terminals** — the user-facing `docs/features/*` docs and the terminal-detection docs `docs/tech/hooks.md` / `hook-server.md` are easy to miss. Run `grep -rl 'iTerm2\|Kitty' docs README.md site` and add the new terminal wherever the list appears; **skip historical `docs/log/*`** post-mortems (point-in-time records — don't backfill them). |

Rules: run `just build` and `just test` after each task. Do **not** run `just run` (the user tests the app). Do **not** commit — the user controls git.

## Phase 4: Verify

- `just build` clean, `just test` all green, `just lint` clean.
- `grep -ri <oldname>` from a cloned bridge to confirm no leftover identifiers (a literal terminal name in a path/bundle id is fine).
- The new terminal's `iconName` is distinct from every other `TerminalType` icon (they render side-by-side in the monitor), and `TerminalTypeTests` asserts it.
- `grep -rl 'iTerm2\|Kitty' docs README.md site/index.html` — every file that enumerates the supported terminals now lists the new one too (historical `docs/log/*` excepted).
- Documented quirks in `docs/tech/<foo>-bridge.md` match the capability matrix from Phase 1 — especially any id transform and the tmux/ssh behavior.
- Confirm `getSessionInfo` honors the three-valued contract (present / `nil` / throw); a bridge that returns `nil` on a transient failure will remove live sessions.
- Hand off for a manual smoke test: select the terminal in the Integration Hub, open sessions, confirm hotkey/GUI activation focuses the right pane, highlight flashes (if in scope), a closed pane is cleaned up on the next cycle, and tmux + ssh sessions activate correctly.

## Examples

### Example: "Let's integrate WezTerm"

1. **Phase 1** — Research `wezterm cli`. Activation: `wezterm cli activate-pane --pane-id N`. Self-discovery: `$WEZTERM_PANE` inside every pane. Info: `wezterm cli list --format json` (has `is_active`, tab/window ids). Highlight: no direct CLI — needs Lua config reacting to user-vars. Focus events: only via Lua `update-status`; hard. Fill the matrix: activate✓, addressing✓ (`WEZTERM_PANE`), getSessionInfo✓ (`cli list`), highlight→GAP (out of scope v1), focus-sync→GAP, close→activation-time cleanup. Present: "WezTerm activation and gone-session cleanup work cleanly via `wezterm cli`; highlight would require the user to add Lua config, so it's out of scope for v1; no focus-sync. OK to proceed?"
2. After sign-off → **Phase 2** design doc: mirror `KittyBridge` (CLI-driven), `.wezterm` case already exists as a detection stub — add the bridge behind it.
3. **Phase 3** — clone `KittyBridge`, swap `kitten @` calls for `wezterm cli`, parse `WEZTERM_PANE`, skip the highlight/watcher work marked out of scope.
4. **Phase 4** — green build/tests, hand off for smoke test.

### Example: capability gap caught early

User: "Add support for Foo terminal." Phase 1 finds Foo has an AppleScript `activate` for its *app* but no way to focus a specific tab, and no per-pane env var — a pane cannot learn its own id. The matrix is fatal: activate is only whole-app, addressing is a hard GAP. The Go/No-Go surfaces it: "Foo can be brought to the front as an app, but Juggler can't target a specific session inside it, and a pane can't report which session it is — so tracking and activation aren't possible. Recommend not proceeding." The user decides before any code is written.

## Troubleshooting

### The terminal's docs don't clearly describe the automation API

**Cause:** Sparse or fast-moving CLI/scripting docs.
**Solution:** Do not guess in the capability matrix. Mark unknown rows "unverified" and say so at the Go/No-Go. If activation or pane self-discovery can't be confirmed, treat it as a GAP until proven otherwise — those two are load-bearing.

### Activation targets the wrong pane, or nothing happens

**Cause:** The id the pane reported doesn't match the id the control API expects — a prefix/suffix or format mismatch (the classic iTerm2 `w1t0p0:UUID` vs bare `UUID` trap).
**Solution:** Match ids the way the codebase already does — `hasSuffix`, not `==`, for iTerm2-style ids. Verify the round-trip in a `<Foo>BridgeTests` case before wiring the UI. See the recurring-trap note in AGENTS.md.

### Live sessions get removed from the cycle

**Cause:** `getSessionInfo` returned `nil` (confirmed-gone) on what was actually a transient failure, so `TerminalActivation` removed a live session.
**Solution:** Honor the three-valued contract — return `nil` only when the terminal *authoritatively* reports the session absent; **throw** on connection/timeout/parse failures. See `terminal-bridges.md` "Detecting a gone session from an opaque error."

### A capability gap is found mid-implementation despite Phase 1

**Cause:** The Phase 1 inventory missed a mechanism, or an API behaves differently than documented.
**Solution:** Stop. Return to Phase 1, update the capability matrix, and re-run the Go/No-Go with the user before continuing. A gap found mid-build is exactly the failure mode this skill prevents — do not paper over it with a stub that appears to work but doesn't.

# Pi Extension

Juggler learns what [Pi](https://pi.dev) (`@earendil-works/pi-coding-agent`) is doing through
**hooklinesinker**, the shared status binary the app bundles — no separate Brew dependency. Pi
has no shell hooks, so hooklinesinker ships a TypeScript **extension** that runs inside the Pi
process, subscribes to Pi's lifecycle events, and shells out to the binary — the same in-process
model as the OpenCode plugin.

## Installation

`hooklinesinker hooks install --agent pi` writes the extension to
`${PI_CODING_AGENT_DIR:-~/.pi/agent}/extensions/hooklinesinker-pi.ts`, substituting the promoted
binary's absolute path into the template, and removes the pre-migration `juggler-pi.ts` in the
same pass.

The extension source lives in hooklinesinker (`assets/pi-hooklinesinker.ts`) and is compiled into
the binary with `include_str!`, so Juggler no longer ships a `.txt` copy in its resources — the
Xcode filesystem-synchronized group can no longer misroute it into Compile Sources.

`PiExtensionInstaller` (`Services/PiExtensionInstaller.swift`) is now a thin delegation to
`HooklinesinkerClient`. Juggler's onboarding flow and `IntegrationHubView` run it automatically.
Pi auto-discovers global extensions from that directory — **no trust step and no feature flag**
(unlike Codex). The user must restart Pi or run `/reload` for a freshly installed extension to
load.

## Lifecycle

Like the OpenCode plugin (and unlike Claude Code's stateless per-event scripts), the extension is a long-lived module. Its default-exported factory runs once when Pi loads it and:

1. Subscribes to Pi lifecycle events via `pi.on(...)`.
2. Observes optional permission-system broadcasts via `pi.events.on(...)`.

Terminal, tmux, git and SSH detection are the binary's job and happen per event, so nothing goes
stale if Pi is re-parented at runtime.

It never intercepts `tool_call` or any `before_*` event, so it cannot influence Pi's behavior. The permission listeners are observational and use literal channel names, with no import or dependency on the permission package.

## Tracked Events

| Pi event | Ingested as | Notes |
|----------|-----------|-------|
| `session_start` | `session_start` | Fires at launch (`reason: "startup"`), before the first prompt — the session appears immediately as `idle`. Also fires on new/resume/reload/fork; re-posting `idle` is correct. |
| `agent_start` | `agent_start` | The agent run begins after a prompt. |
| `agent_settled` | `agent_settled` | Pi's recommended "done" signal — unlike `agent_end`, Pi will not auto-retry/compact/continue after it. |
| `permissions:ui_prompt` | `permission_prompt` | `@gotgenes/pi-permission-system` is about to show a user-facing permission prompt. The session becomes cyclable as `permission`. |
| `permissions:decision` | `permission_resolved` | A user-facing permission gate reached a decision. Silent policy and session decisions are ignored. |
| `session_before_compact` | `session_before_compact` | Compaction starting. |
| `session_compact` | `session_compact_idle` / `session_compact_working` | The extension reads `event.reason`: a manual `/compact` leaves the session idle; a `threshold`/`overflow` compaction is mid-turn and resumes work. |
| `session_shutdown` | `session_shutdown` | Ingested **only** for a UI-owning session when `event.reason === "quit"`. Child sessions and new/resume/reload/fork do not remove the terminal session. |

## Payload

The extension does not talk to Juggler's HTTP server. It runs
`hooklinesinker ingest --agent pi --event <event>` and writes `{"session_id": "..."}` to its
stdin; the binary enriches that into a protocol-1 status record and POSTs it to Juggler's sink.
See [Claude Code Hooks](hooks.md#payload-contract) for the record shape — it is shared by all
four agents.

`session_id` is Pi's session id (`ctx.sessionManager.getSessionId()`), carried as secondary
metadata — Juggler keys sessions by the terminal session id. Permission-system payload details
such as commands, paths, and prompt messages are never forwarded; only the synthesized event
name is.

## Permission-System Integration

Pi core has no native permission concept, so stock Pi sessions never produce a permission state. The optional `@gotgenes/pi-permission-system` package exposes public `permissions:ui_prompt` and `permissions:decision` channels on Pi's shared event bus. Juggler observes those package-specific broadcasts without importing the package; if it is absent, the channels never fire and normal Pi tracking is unchanged.

The extension tracks pending prompt request IDs. A UI prompt records its ID and posts `permission_prompt`; a later user-facing decision consumes one pending prompt and posts `permission_resolved` when none remain. Silent policy decisions, decisions without a pending prompt, and lifecycle events from non-UI child sessions are ignored. Permission payload details and outcomes are not forwarded to Juggler.

Permission resolution maps to `working`, not `idle`, because one tool call can encounter more gates and Pi can continue executing tools or model turns after either approval or denial. `agent_settled` clears pending prompts and remains the definitive idle signal. The decision broadcast is uncorrelated and local to a session event bus, so forwarded subagent prompts can remain `permission` until another parent event or `agent_settled` arrives. The extension unregisters both event-bus listeners during `session_shutdown` because Pi preserves its shared event bus across `/reload`.

## Capability Gaps

- **Other permission extensions:** Juggler supports the public event contract from `@gotgenes/pi-permission-system`; unrelated permission extensions remain `working` unless they emit compatible channels.
- **Session removal on hard kill:** `session_shutdown` fires on graceful exit (Ctrl+C/D, SIGHUP, SIGTERM) but not on SIGKILL or an abruptly closed window — the terminal-bridge cleanup path is the backstop, same as Claude Code's `SessionEnd`.

## Failure Handling

Every ingest is spawned with a kill timer and its failures are swallowed, so a missing, hanging or
erroring binary cannot block Pi. Ingests share a promise queue so rapid prompt/decision sequences
reach Juggler in event order. `session_shutdown` is awaited so prior state changes and the removal
land before Pi exits.

The extension's contract tests live in hooklinesinker (`tests/ts_adapters.rs`, driving
`tests/assets_harness.mjs`) and require Node.js 22.6 or newer for native TypeScript type
stripping.

## Gotchas

- **Restart / `/reload` required**: a newly installed extension only loads on the next Pi start or `/reload`.
- **The extension embeds an absolute binary path**: it is generated at install time from the promoted binary. Moving `~/.local/share/hooklinesinker` breaks it; reinstall rather than editing the file.
- **The sink URL is registered, not embedded**: Juggler's port comes from `install --consumer juggler --sink ...`, so a test instance on another port re-registers rather than editing the extension.

---

[← Back to Tech Overview](overview.md)

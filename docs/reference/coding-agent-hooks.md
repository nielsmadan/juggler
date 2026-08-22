# Coding Agent Hook & Plugin APIs

How the five coding agents Juggler tracks — Claude Code, Codex, OpenCode, Pi, and Antigravity —
actually emit lifecycle events, and where each one's behavior diverges from its own docs.

This file covers the **external** agents. How Juggler consumes them is in
[`docs/tech/hooks.md`](../tech/hooks.md), [`codex-hooks.md`](../tech/codex-hooks.md),
[`opencode-plugin.md`](../tech/opencode-plugin.md), [`pi-extension.md`](../tech/pi-extension.md),
and [`antigravity-hooks.md`](../tech/antigravity-hooks.md).

- [Registration and contract at a glance](#registration-and-contract-at-a-glance)
- [Event coverage](#event-coverage)
- [Claude Code](#claude-code)
- [Codex](#codex)
- [OpenCode](#opencode)
- [Pi](#pi)
- [Antigravity](#antigravity)
- [Cross-agent gotchas](#cross-agent-gotchas)
- [Upstream](#upstream)

## Registration and contract at a glance

| | Claude Code | Codex | OpenCode | Pi | Antigravity |
|---|---|---|---|---|---|
| Mechanism | shell hooks | shell hooks | TS plugin (in-process) | TS extension (in-process) | shell hooks |
| Registration file | `~/.claude/settings.json` | `~/.codex/hooks.json` | presence in `~/.config/opencode/plugins/` | presence in `${PI_CODING_AGENT_DIR:-~/.pi/agent}/extensions/` | `~/.gemini/config/hooks.json` |
| Keyed by | `hooks[<Event>]` array | `hooks[<Event>]` array | — | — | top-level `"juggler"` key |
| Session id field | `session_id` | `session_id` | four possible paths (see below) | `ctx.sessionManager.getSessionId()` | `conversationId` |
| Field casing | snake_case | snake_case | camelCase (`sessionID`) | n/a (API call) | **camelCase** |
| Hook timeout | 5 (seconds) | 5 s, but `SessionEnd` clamped to 3 | n/a | n/a | 5 (seconds) |
| Reads hook stdout? | no | no | n/a | n/a | **yes — `Stop` requires a `decision`** |
| Gate before hooks run | none | feature flag **and** per-hook trust record | none | none (restart or `/reload`) | none |
| Min version | not established | ≥ 0.114; `SessionEnd` ≥ 0.145 | not established | Node ≥ 22.6 to run the `.ts` extension | ≥ 1.0.8 |

Only two of the five use a plain "drop a script in, it runs" model. Codex gates hooks behind two
separate mechanisms; the two TypeScript agents run in-process and so have no stdin/stdout contract
at all.

## Event coverage

What each agent can actually tell us. **GAP** means the agent emits nothing usable for that state.

| Juggler needs | Claude Code | Codex | OpenCode | Pi | Antigravity |
|---|---|---|---|---|---|
| session create | `SessionStart` (at launch) | `SessionStart` (**at first prompt**) | `session.created` (unreliable — see below) | `session_start` (at launch) | **GAP** |
| working | `PreToolUse`, `UserPromptSubmit` | `PreToolUse`, `UserPromptSubmit` | `session.status.busy` | `agent_start` | `PreInvocation` |
| idle | `Stop` / `StopFailure` | `Stop` | `session.idle`, `session.error` | `agent_settled` | `Stop` (per **turn**) |
| permission | `PermissionRequest` | `PermissionRequest`, `request_user_input` tool | `permission.asked` | **GAP in core** — needs third-party package | **GAP** |
| compaction | `PreCompact` | `PreCompact`, `PostCompact` | `session.compacted` | `session_before_compact`, `session_compact` | **GAP** |
| session remove | `SessionEnd` | `SessionEnd` (≥ 0.145) | `session.deleted`, `server.instance.disposed` | `session_shutdown` (graceful only) | **GAP** — falls back to terminal-bridge cleanup |

No agent fires an event on user interrupt (ESC) or on a CLI crash. Antigravity is the only one with
no session lifecycle at all, which is why an Antigravity session first appears as `working` rather
than `idle`.

## Claude Code

**Documented.** 11 registrable events, declared in `settings.json` under `hooks[<Event>]` as
`{matcher?, hooks: [{type, command, timeout}]}` groups. `timeout` is in **seconds**. Events with
"for any tool" semantics (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`,
`PreCompact`) take `"matcher": "*"`. Payload arrives as JSON on stdin with the event name in `$1`.

**Verified — `SubagentStop` fires *after* `Stop`, 5–10 s late.** Subagent cleanup runs in a
background process, so the real order is `SubagentStart → Stop → SubagentStop`, not the documented
nesting. Established by this project; recorded in
[`docs/tech/hooks.md`](../tech/hooks.md) (2026-08-09). Juggler ignores `SubagentStop` entirely and
strips any pre-existing registration for it on every install.

**Documented — `Stop` does not fire on API errors.** Overload, rate-limit, auth, billing, server
and invalid-request failures fire `StopFailure` instead. An integration that only watches `Stop`
leaves a session stuck in `working` after any API error.

**Gotcha — payloads are large.** `PostToolUse` carries the full `tool_input` and `tool_result`.
Anything forwarding the raw payload over a size-capped transport will eventually drop events; the
notify script extracts three fields and discards the rest.

## Codex

Codex is the most gated of the five, and the gating is where integrations break.

**Documented — two independent prerequisites.** `hooks.json` is ignored entirely unless
`[features] hooks = true` is set in `~/.codex/config.toml`. Separately, Codex refuses to run a
newly registered hook until it is trusted — normally via the `/hooks` TUI, or by writing a
`[hooks.state]` record whose `trusted_hash` matches Codex's own fingerprint. Registering a hook is
therefore not the same act as enabling it, and re-syncing `hooks.json` never grants trust.

**Documented — the trust fingerprint.** `sha256:` over sorted-key compact JSON of the form
`{"event_name":"<snake>","hooks":[{"async":false,"command":"<cmd>","timeout":N,"type":"command"}]}`.
The group index in the trust key is **not always 0** — a user's own hook for the same event takes
group 0 and pushes ours to group 1.

**Verified — `SessionStart` fires at the first prompt, not at launch.** A TUI left open for 20 s
with no prompt fires no hook at all; `SessionStart`/`UserPromptSubmit`/`Stop` all arrive the moment
a prompt is sent. The `source: "startup"` field describes *why* the session was created, not when
the process launched — Codex creates sessions lazily. Verified against **Codex 0.145.0**.

**Verified — `SessionEnd` timeouts are clamped to 3 s, and the clamp reaches the trust hash.**
Codex caps `SessionEnd` hook timeouts at 3 s (logging `clamping SessionEnd hook timeout to 3s`) and
computes the trust fingerprint from the *post-clamp* value. Registering it at the usual 5 s writes a
well-formed entry whose `trusted_hash` Codex will never match: the install looks green, and the hook
silently never runs. Recorded in [`docs/tech/codex-hooks.md`](../tech/codex-hooks.md) (2026-08-11).
This is the single most expensive external quirk in the project — it fails **silently and
green**.

**Verified — `SessionEnd` does not fire on `/new`, `/clear`, fork, resume, or compaction.** Those
produce a bare `SessionStart` with a corresponding `source`. The abandoned thread fires its own
`SessionEnd` later — on idle-unload (~30 min) or at quit — so a late `SessionEnd` may refer to a
thread the user already left, not the live session.

**Gotcha — no error event.** Codex collapses successful and failed turn endings into one `Stop`;
the error context is in the payload, not the event name.

**Gotcha — `request_user_input` is a tool, not an event.** Codex blocks *inside* the tool call
waiting for the answer, so a permission-like pause is only visible by matching
`tool_name == request_user_input` on `PreToolUse`/`PostToolUse`.

**Gotcha — `PermissionRequest` does not identify the reviewer.** Nothing in the payload
distinguishes an automatic Auto Review approval from a real prompt to the user. The
`approvals_reviewer = "auto_review"` setting in `config.toml` is the only signal, and it is not
visible if the user set it via a profile or a command-line override.

**Gotcha — `config.toml` has no Swift TOML parser.** Edits are targeted string surgery, which is
why uninstall prefers restoring a backup over unpicking the file.

## OpenCode

**Documented.** A long-lived in-process TypeScript plugin loaded from the plugins directory at
startup — no registration file, no approval, no per-event subprocess. Events arrive as JS objects on
a subscribed handler.

**Documented — `session.status` is a parent event.** The real status is nested at
`event.properties.status.type` (`idle`, `busy`, `retry`, …). A consumer that only reads the
top-level event name sees one undifferentiated event.

**Verified — resumed sessions never fire `session.created`.** When OpenCode resumes a previous
session the real creation event is simply not emitted, so a plugin that waits for it tracks nothing.
The workaround is to fire a synthetic creation event on plugin load. Recorded in
[`docs/tech/opencode-plugin.md`](../tech/opencode-plugin.md) (2026-08-09) and flagged there as
load-bearing: removing it silently breaks tracking for every resumed session.

**Verified — the session id lives at four different paths.** Depending on event type it appears as
`event.properties.sessionID`, `event.properties.info.id`, `event.session_id`, or `event.sessionID`.
There is no single guaranteed field; consumers must try all four.

**Gotcha — `session.idle` and `session.error` are distinct.** Treating only `session.idle` as
"turn over" leaves a session stuck in `working` after a model or API error.

**Gotcha — the plugin process outlives its environment.** Because it is loaded once rather than
re-invoked per event, anything captured from the environment at load (terminal identity, cwd) goes
stale if the process is re-parented. Restarting OpenCode is the only refresh.

## Pi

**Documented.** A long-lived in-process TypeScript extension auto-discovered from
`${PI_CODING_AGENT_DIR:-~/.pi/agent}/extensions/`. No trust step and no feature flag — but **no
hot-load either**: a freshly installed extension needs a Pi restart or `/reload`.

**Documented — `agent_settled`, not `agent_end`, is the "done" signal.** Pi may auto-retry,
compact, or continue after `agent_end`; it will not after `agent_settled`. Picking the
obvious-looking event here is wrong.

**Documented — `reason` fields carry the real meaning.** `session_compact` distinguishes `manual`
(idle afterwards) from threshold/overflow compaction (still working afterwards).
`session_shutdown` distinguishes `quit` (a real termination) from new/resume/reload/fork, which keep
the session alive.

**Verified — Pi core has no permission concept.** Stock Pi never produces a permission state at
all. Permission events come only from the optional third-party `@gotgenes/pi-permission-system`
package, observed via its public bus channels `permissions:ui_prompt` and `permissions:decision`
without importing it. If the package is absent the channels never fire.

**Gotcha — the permission decision carries no correlation id.** The decision broadcast is local to
a session event bus and is not tied to the prompt it resolves, so with multiple gates or a
subagent-forwarded prompt, a session can sit in `permission` until some later parent event or
`agent_settled` arrives. A paired `permissions:ui_prompt_resolved` event carrying a `requestId` has
been *proposed* upstream ([plan](../superpowers/plans/2026-07-31-pi-permission-prompt-resolution.md))
but as of 2026-08-22 does not exist — the shipped extension still listens only on the two channels
above.

**Gotcha — the event bus survives `/reload`.** Listeners must be explicitly unregistered on
`session_shutdown` or they accumulate duplicates across reloads.

**Gotcha — Pi spawns non-UI child sessions on the same bus.** They must be filtered on
`ctx.hasUI` or headless children are tracked as if they were real sessions.

**Gotcha — `session_shutdown` is graceful-only.** It fires on Ctrl+C/D, SIGHUP and SIGTERM, but not
on SIGKILL or an abruptly closed window.

## Antigravity

The thinnest hook surface of the five, and the only one that can break the agent.

**Documented — five events exist, and three are actively unsafe or useless.** `PreInvocation` and
`Stop` are the only turn boundaries. `PreToolUse` requires a `decision` response and can block every
tool call if the hook misbehaves; `PostToolUse` and `PostInvocation` fire per-tool / per-model-call
rather than per turn.

**Documented — `Stop` reads the hook's stdout and acts on it.** `{"decision":"stop"}` allows the
stop; emitting `"continue"` traps the agent back into its loop. The response must be emitted
unconditionally and independently of any other work the hook does, or a slow or failed side effect
can hang the agent. `PreInvocation` accepts `{}` as a safe no-op.

**Verified — no session-start and no session-end event exists.** Nothing fires when a conversation
begins or ends. A session first becomes visible on its first `PreInvocation` (already `working`,
never a fresh `idle`), and nothing signals its end — removal must come from the terminal side.
Recorded in [`docs/tech/antigravity-hooks.md`](../tech/antigravity-hooks.md) (2026-07-26). This gap
was found only after a full integration had been built, and is why
[`.claude/skills/integrate-coding-agent`](../../.claude/skills/integrate-coding-agent/SKILL.md)
front-loads a capability check.

**Verified — `Stop` fires per turn, not at session close.** It marks the execution loop terminating
(`terminationReason: "model_stop"`).

**Verified — `$PWD` inside the hook is wrong.** Antigravity runs hooks from its own config
directory, so the process cwd is `~/.gemini/config`. The real working directory is `workspacePaths[0]`
on stdin. Without that substitution every session reports `~/.gemini/config` and never resolves a git
branch.

**Verified — the config file is shared with the Antigravity 2.0 IDE.** `~/.gemini/config/hooks.json`
serves both surfaces, so a CLI-oriented hook also fires for IDE sessions. Those carry no terminal
environment, which is the only thing that keeps them out of a terminal-keyed tracker.

**Gotcha — camelCase, alone among the five.** `conversationId` and `transcriptPath`, not
`session_id` and `transcript_path`.

**Gotcha — no user-prompt event.** There is no `UserPromptSubmit` equivalent, so the only proxy for
"the user re-engaged" is a `working` event, which also fires on every model call inside a turn.

**Gotcha — the config path moved.** Versions before 1.0.8 used a different global hooks path.

## Cross-agent gotchas

- **Session-id field names and casing differ across all five.** Any unified ingress has to
  normalize at the edge.
- **"Session start" means three different things.** At process launch (Claude Code, Pi), at the
  first prompt (Codex), or never (Antigravity). An integration that assumes launch-time creation
  shows sessions late or not at all.
- **Turn boundaries versus model calls.** Several agents expose per-tool or per-model-call events
  that look like turn boundaries and are not. Antigravity's `Stop` and Pi's `agent_settled` are the
  real ones for those agents; `PostToolUse`-shaped events never are.
- **A green install is not a working install.** Codex's trust-hash clamp is the worst case, but the
  general pattern — registration succeeds, the agent silently declines to run the hook — applies to
  every gated agent.

## Upstream

| Agent | Docs | Source / releases |
|---|---|---|
| Claude Code | [hooks reference](https://docs.claude.com/en/docs/claude-code/hooks), [guide](https://docs.claude.com/en/docs/claude-code/hooks-guide) | — |
| Codex | docs in-repo (`docs/hooks.md`) | [openai/codex](https://github.com/openai/codex) |
| OpenCode | [plugins](https://opencode.ai/docs/plugins) | — |
| Pi | [pi.dev](https://pi.dev) | `@earendil-works/pi-coding-agent`; permissions via `@gotgenes/pi-permission-system` |
| Antigravity | [CLI features](https://antigravity.google/docs/cli/features) | — |

Versions present on the maintainer's machine when this file was last revised (2026-08-22):
Claude Code 2.1.239, Codex 0.149.0, Pi 0.84.1, Antigravity (`agy`) 1.1.11.

---

[← Reference index](overview.md)

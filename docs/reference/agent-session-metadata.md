# Agent Session Metadata in Hooks

Which per-session details beyond lifecycle state (model, effort, tokens, context, cost, timing,
permission mode) each coding agent exposes **on its hook or plugin surface**, for showing them in
the session list.

Juggler takes everything it knows about a session from hooks: hooklinesinker's status sink for
Claude Code, Codex, OpenCode, Pi, Droid, Qwen, Kimi and Cursor, and its own notify script for
Antigravity. It never reads agent transcripts, session files, databases or logs, even though
`transcriptPath` arrives on the wire. Every field below is a hook input or an adapter API, not a
transcript field.

- [What reaches Juggler today](#what-reaches-juggler-today)
- [Row slots per agent](#row-slots-per-agent)
- [Native sources per agent](#native-sources-per-agent)
- [Turns and run time](#turns-and-run-time)
- [Per agent](#per-agent)
- [Gotchas](#gotchas)
- [Sources and versions](#sources-and-versions)

## What reaches Juggler today

hooklinesinker reads a small allowlist of native fields in a lenient second pass (a missing or
wrong-typed field is skipped, text is sanitized and capped at 120 characters) and forwards them on
every status record as `session.title`, `model`, `effort`, `permissionMode` and an `activity` object
(`tool`, `problem`, `subagents`, `contextPercent`, `turns`). Prompt text, tool input and output and message
bodies are never read. Merge rules (what is kept, cleared or reset on a new turn, compaction or
`/clear`) are in hooklinesinker's
[status lifecycle](https://github.com/nielsmadan/hooklinesinker/blob/main/docs/status-lifecycle.md#session-details),
and the per-agent field list is in its
[hooks and adapters](https://github.com/nielsmadan/hooklinesinker/blob/main/docs/hooks-and-adapters.md#session-details).
Juggler decodes the keys leniently (`HooklinesinkerStatus.sessionDetails`), keeps them on
`Session.details`, and ignores a record older than the one it holds. Some fields are renamed on
the way in:

| Wire | `SessionDetails` |
|---|---|
| `session.title` | `agentTitle` |
| `session.model`, `effort`, `permissionMode` | `model`, `effort`, `permissionMode` |
| `activity.tool` | `currentTool` |
| `activity.problem` | `lastProblem` |
| `activity.subagents` | `subagentCount` |
| `activity.contextPercent` | `contextPercent` |
| `activity.turns` | `turns` (nil when the record has no `activity`) |
| `process.startedAt` | `processStartedAt` |
| `observedAt` | `observedAt` |

Antigravity is the exception: Juggler's own notify script forwards `modelName` as `hookInput.model`
and `terminationReason` as `hookInput.termination_reason`, and `HookEventMapper.antigravityDetails`
turns them into the model and the last problem. The script sanitizes with hooklinesinker's rules:
it drops control characters and format characters except the zero-width joiner, caps the text at
120 characters, removes a joiner or combining mark left dangling only when the cap cut the text,
and omits a value that ends up empty. It decides by Unicode category where hooklinesinker uses a
fixed range table, so the two can differ for rarely used marks. A `terminationReason` other than
`model_stop` becomes the problem; the next `PreInvocation` clears it.
See [Antigravity Hooks](../tech/antigravity-hooks.md).

## Row slots per agent

What each Session Monitor slot shows for each agent today. `-` means the agent gives Juggler nothing
for that slot and the cell stays empty. See [Session Monitor](../features/main-window.md#row-details).

| Slot | Claude | Codex | Droid | Qwen | Kimi | Pi | OpenCode | Antigravity |
|---|---|---|---|---|---|---|---|---|
| Agent Session Title | yes | - | - | - | yes | yes | - | - |
| Model | yes | yes | - | start model | start model | yes | - | yes |
| Effort | yes | - | - | - | - | yes | - | - |
| Permission Mode | yes | yes | yes | yes | - | - | - | - |
| Current Tool | yes | yes | yes | yes | yes | - | - | - |
| Last Problem | yes | interrupted only | - | yes | yes | interrupted only | - | yes |
| Subagents | yes | yes | yes | - | - | - | - | - |
| Context % | - | - | - | yes | - | yes | - | - |
| Turns | yes | yes | yes | yes | yes | yes | - | counted by Juggler |
| Run Time | yes | yes | yes | yes | yes | yes | yes | - |

- **Subagents** is Codex, Droid and Claude only. Pi and OpenCode track children inside their
  adapters for status, but report no count.
- **Qwen and Kimi model** is the model at `SessionStart`; a mid-session switch is not seen.
- **Effort** is only Claude (`effort`) and Pi (`thinkingLevel`). Claude's disappears when the
  model changes until the event sets it again.
- **OpenCode** has no details beyond run time, because its adapter forwards none and
  hooklinesinker has no OpenCode turn-start event to count.
- **Antigravity** model and last problem come from Juggler's script, not hooklinesinker.

## Native sources per agent

This table is what each agent exposes on its hook or plugin surface, forwarded or not. `*` marks a
source on an event or API the integration does not subscribe to today.

| Agent | Model | Effort | Tokens / context | Cost | Duration | Permission mode |
|---|---|---|---|---|---|---|
| Claude Code | `SessionStart.model` (may be omitted); `PostModelSwitch.to_model`* | `effort.level` on tool events and `Stop` | none per turn; `context_tokens` on resume `SessionStart` and model switch* | `estimated_cache_write_usd` on resume/switch only | `duration_ms` per tool | prompt, tool, permission and `Stop` events |
| Codex | `model` on every event except `SessionEnd` | — | `PostModelRequest.token_usage`* per request; no window size | — | — | most events, but only `default`/`bypassPermissions` in practice |
| OpenCode (V1 plugin API) | `chat.message` model and `variant`*; `message.updated` `modelID`* | `variant`* | `message.updated` tokens*; window from `chat.params` `model.limit.context`* | `message.updated` `cost`* | message `time.created/completed`* | — |
| Pi | `ctx.model`; `model_select`* | `ctx.thinkingLevel`; `thinking_level_select`* | `ctx.getContextUsage()` → `{tokens, contextWindow, percent}` | `message_end` `usage.cost`* | `message_end` `durationMs`* | — (none in core) |
| Droid | — | — | `PreCompact.estimated_tokens` | — | `Stop.elapsed_time`, `SessionEnd.session_duration_ms` | every event |
| Qwen Code | `SessionStart.model` | — | `Stop.context_usage`, `context_limit`, `input_tokens` | — | `timestamp` on every event | `SessionStart`, tool and permission events |
| Kimi Code | `SessionStart.model` (default model) | — | `PreCompact.token_count`, `PostCompact.estimated_token_count` | — | `SessionHeartbeat.uptime_ms`* | — |
| Antigravity | `modelName` on every event | — | — | — | — | — |

Summary by item:

- **Model**: every agent except Droid. It is per event only for Codex, Pi and Antigravity; the
  others report it at session start.
- **Effort**: Claude Code, Pi, and OpenCode's `variant` (not forwarded).
- **Context %**: available directly only from Pi and Qwen. OpenCode needs it computed from
  tokens and the model's window; the other agents expose no context size at all.
- **Cost**: Pi and OpenCode only.

## Turns and run time

Two slots come from no agent field:

- **Turns**: hooklinesinker counts a binding's turn starts (`UserPromptSubmit`; Kimi
  `TurnStarted`; Pi `agent_start`; Cursor `beforeSubmitPrompt`) and sends the count as `activity.turns`, so a turn that
  starts while the session is still held working by background work counts too, and a new
  conversation (including after `/clear`) starts at 0. Juggler shows that count whenever the
  record carries `activity`. For Antigravity, and for records from a hooklinesinker too old to
  send `activity`, Juggler counts itself in `Session.turnCount` (`SessionManager.isNewTurn`): a
  turn-start event (`UserPromptSubmit`, Cursor's `beforeSubmitPrompt`, `TurnStarted`,
  `agent_start` or Antigravity's `PreInvocation`) that takes the row from `idle` to `working`,
  creates the row already `working`, or, on a prompt submit only, wakes a backburnered row. Launch hydration does not
  count, and rows are not persisted, so that count is turns since Juggler first saw the session.
- **Run time**: the time since `process.startedAt` on the status record, the owning agent process's
  start time. For OpenCode and Pi it marks the start of the process, not of the conversation; one
  process can host several. Antigravity's script sends no process identity, so it has no run time.

## Per agent

### Claude Code

**Documented.** Common fields include `session_id`, `prompt_id`, `transcript_path`, `cwd`,
`hook_event_name` and, on most events, `permission_mode`. `effort` is "Present for events that fire
within a tool-use context, such as `PreToolUse`, `PostToolUse`, `Stop`, and `SubagentStop`, when
the current model supports the effort parameter" (added 2.1.133). On the model: "Only `SessionStart`
hooks can receive a `model` field, and Claude Code doesn't always include it." Upstream recommends
`PostModelSwitch` (`from_model`, `to_model`) to follow mid-session changes. `Stop` carries
`last_assistant_message`; `SessionStart` and `UserPromptSubmit` carry `session_title` when one is
set. `PreCompact` carries no token counts.

### Codex

**Documented** (generated input schemas in `codex-rs/hooks/schema/generated/`). `model` is the model
slug and appears on every event except `SessionEnd`; `turn_id` is on every event except
`SessionStart` and `SessionEnd`. `Stop` and `SubagentStop` carry `last_assistant_message`. The
unregistered `PostModelRequest` carries `token_usage` (`input_tokens`, `cached_input_tokens`,
`output_tokens`, `reasoning_output_tokens`, …) for one model request, not one turn. No event
carries the context-window size or reasoning effort.

### OpenCode

**Documented** for the V1 plugin API the adapter uses (SDK 1.17.0). The adapter subscribes to
`session.updated` but not to message events. `message.updated` → `AssistantMessage` carries
`modelID`, `providerID`, `cost`, `tokens{input, output, reasoning, cache{read, write}}` and
`time{created, completed}`. The `chat.params` hook receives `model.limit.context`. The V2 API
(`ctx.event.subscribe()`) adds `session.usage.updated` with cumulative `cost` and `tokens`,
`session.step.ended` per step, and `session.model.selected`.

### Pi

**Documented** (`@earendil-works/pi-coding-agent` 1.4.0 `extensions/types.d.ts`).
`ctx.getContextUsage()` returns `tokens: number | null` ("null if unknown (e.g. right after
compaction…)"), `contextWindow` and `percent`. It can be called from the `agent_settled` handler
the adapter already has. `message_end` and `turn_end` carry the `AssistantMessage` with `model`,
`provider`, `thinkingLevel`, `usage{input, output, cacheRead, cacheWrite, totalTokens, cost}` and
`durationMs`. No API gives cumulative session totals; they would have to be summed in the adapter.

### Factory Droid

**Documented**, with the binary's payload builders checked. Common fields include
`permission_mode` (`off`, `spec`, `auto-low`, `auto-medium`, `auto-high`). `Stop` carries
`tool_execution_count` and `elapsed_time`; the binary computes it as
`Date.now() - executionStartTime`, so it is in milliseconds. `SessionEnd` carries
`session_duration_ms` and `message_count`. No payload has a model, effort, token or cost field.

### Qwen Code

**Documented** (`packages/core/src/hooks/types.ts`, v0.23.0). Every event carries `timestamp`.
`interface StopInput extends HookInput, Partial<ContextUsageData>` adds `context_usage` (a
fraction), `context_limit` and `input_tokens`. These measure the last prompt against the context
window. `SessionStart` carries `model` and `permission_mode`; main adds `permission_mode` to every
event and `duration_ms` to `PostToolUse`.

### Kimi Code

**Documented** (`MoonshotAI/kimi-code` 2.4.0, `packages/agent-core-v2/src/features/externalHooks/`).
Every event carries `session_title` and `client_type`. `SessionStart` carries the default `model`.
Token counts appear only around compaction.

### Antigravity

**Documented** (Antigravity hooks docs, `agy` 1.1.11). Every event carries `modelName`. The
docs' example is `gemini-3.6-flash-medium`, but the help text bundled in the binary uses `auto`.
`Stop` carries `terminationReason` and `fullyIdle`. There are no token, cost, effort or duration
fields.

## Gotchas

- **Gotcha — Claude Code's model can vanish.** It arrives on `SessionStart`, is omitted after
  `/clear` and on recovery, and goes stale after `/model` unless `PostModelSwitch` is subscribed.
  hooklinesinker subscribes to it (it fires on Claude Code 2.1.251 and later) and carries the last
  known model across `/clear`.
- **Gotcha — a model name can carry the effort.** Antigravity's `gemini-3.6-flash-medium` encodes
  the level in the name, and `auto` encodes nothing. Display it as reported rather than parsing it.
- **Gotcha — per-request is not per-turn.** Codex `PostModelRequest` and Pi/OpenCode message
  events report one model call. A turn total has to be summed until the turn settles.
- **Gotcha — token totals are mostly cache reads.** In agentic sessions nearly all input tokens
  are cached context re-sent each request, so a raw turn total is dominated by context size.
  Output tokens or context % mean more.
- **Gotcha — Codex `permission_mode` is binary.** The schema lists five modes, but
  `hook_permission_mode()` only produces `default` or `bypassPermissions`.
- **Gotcha — OpenCode 2.x does not run V1 plugins.** The v2.2.0 migration guide says: "V1 plugin
  implementations do not run in V2." The hooklinesinker adapter is a V1 plugin, so any OpenCode
  metadata work depends on porting it to `Plugin.define` and `ctx.event.subscribe()`.

## Sources and versions

Inspected 2026-10-29 against the versions installed on the maintainer's machine:

| Agent | Version | Source |
|---|---|---|
| Claude Code | 2.1.312 | [hooks reference](https://code.claude.com/docs/en/hooks), CHANGELOG |
| Codex | 0.165.0 | [openai/codex](https://github.com/openai/codex) `rust-v0.165.0`, `codex-rs/hooks/` |
| OpenCode | 2.2.0 (SDK types 1.17.0 for V1) | [anomalyco/opencode](https://github.com/anomalyco/opencode) `v2.2.0` |
| Pi | 1.4.0 | installed `@earendil-works/pi-coding-agent` type definitions |
| Droid | 0.251.0 | [hooks reference](https://docs.factory.ai/harness/hooks.md), installed binary |
| Qwen Code | 0.23.0 | [QwenLM/qwen-code](https://github.com/QwenLM/qwen-code) `v0.23.0` |
| Kimi Code | 2.4.0 (not installed) | [MoonshotAI/kimi-code](https://github.com/MoonshotAI/kimi-code) |
| Antigravity | 1.1.11 | [hooks docs](https://antigravity.google/docs/hooks), installed binary |

`MoonshotAI/kimi-cli` is the archived Python CLI; the hook events hooklinesinker registers
(`TurnStarted`, `PermissionResult`, `Interrupt`) belong to `kimi-code`.

---

[← Reference index](overview.md)

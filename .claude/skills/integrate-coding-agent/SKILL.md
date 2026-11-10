---
name: integrate-coding-agent
description: Methodical workflow for adding a new coding-agent integration to Juggler. Use when adding support for a new coding agent or CLI — e.g. "integrate the Foo CLI", "add support for a new agent", "track a new agent's sessions". Since the hooklinesinker migration most of the work lives outside Juggler; this skill routes you to the right repo and keeps the Juggler-side checklist honest.
---

# Integrate Coding Agent

## Overview

Juggler no longer normalizes agent events itself. **hooklinesinker** (bundled binary, separate
repo at `~/wrksp/hooklinesinker`) owns hook installation, event→phase mapping, and the session
ledger; Juggler consumes protocol-1 status events over its sink and renders them. Adding an
agent therefore forks on one question:

**Is the agent already supported by hooklinesinker?** (`hooklinesinker hooks install --agent`
accepts it / it appears in hooklinesinker's README agent table.)

- **Yes** → Path A below. Juggler-side only, a few hours including docs.
- **No** → Path B: add it to hooklinesinker first, then come back to Path A.
- An agent that *cannot* go through hooklinesinker (no child-process hooks and no scriptable
  plugin API) needs a bespoke legacy bridge like Antigravity's — that is a design discussion
  with the user, not a checklist; read `AntigravityHooksInstaller.swift` and the legacy
  `UnifiedHookPayload` path in `HookServer.swift` before proposing one.

## Path A: agent already in hooklinesinker

No notify script, no installer, no `AppStorageKeys` flag (only opt-in agents — Codex,
Antigravity — have one), no `uninstall.sh` block. `HookEventMapper` needs entries only when the
agent's event names differ from Claude's (see Behavior checks). The full set:

### Code

| File | Change |
|---|---|
| `juggler/Services/HooklinesinkerClient.swift` | Add the `HooklinesinkerAgent` case. Raw value **must equal the wire name** (kebab-case, from hooklinesinker's `src/protocol.rs`); the argv test over `allCases` then pins it automatically. |
| `juggler/Models/Session.swift` | Add `agentShortName` (2 letters, e.g. `DR`) and `agentDisplayName` cases. |
| `juggler/Views/HookAgentSetup.swift` | Add a `HookAgentSetup` entry to `all` (icon, config path, whether it reports permission, optional startup hint). The integration hub card, its setup sheet and the Settings section all come from this list. |
| `scripts/install-remote.sh` | Add a detection block (config dir from hooklinesinker's `src/hooks.rs` roots, plus the CLI on `$PATH`) and extend the "Looked for:" line. Remote hosts get hooks from this script, not from the UI; `theInstallerInstallsEveryAgentJugglerSupports` fails until it is there. |

Quirk hints in the UI: if the agent only reads hooks at startup (Droid does), set the entry's
`startupHint`. Set `reportsPermission: false` when the agent has no permission hook (Cursor).

`HookServer` drops statuses from agents that are not `HooklinesinkerAgent` cases, so a new
agent shows nothing until its case exists.

### Behavior checks

- **Event names**: Juggler reads the raw `event` for backburner wake, pane re-binding, turn
  counting and session identity. Look up the agent's table in hooklinesinker's `src/events.rs`.
  If its prompt-submit event is not `UserPromptSubmit`, add it to
  `HookEventMapper.promptSubmitEvents` (Cursor: `beforeSubmitPrompt`). Any other turn-start event
  goes in `turnStartEvents`. If its session-start or prompt event differs from `SessionStart` /
  `UserPromptSubmit`, add a case to `HookEventMapper.establishesSessionIdentity`.
- **Trust/consent**: hooklinesinker never touches trust state. If the agent has a Codex-style
  trust or feature-flag gate, Juggler must own it — stop and design that with the user.

### Tests

Mirror the existing per-agent tests: decode passthrough in `HookServerTests`
(`newAgentsPassThroughUnchanged` pattern), a removal-path case in `IntegrationTests` if the
agent's end event differs from the others. The `allCases` argv test covers the wire name for
free.

### Docs sweep (easy to forget — grep for an existing agent name to find every list)

- `README.md`: intro line, badge row, "Open your sessions" step, **Coding agents** line
  (include a minimum agent version if hooklinesinker documents one), and the per-agent bullet
  list under **Agent Integration**.
- `juggler/Views/SettingsView.swift`: the SSH tab's step 3 names the agents the remote
  installer covers.
- `docs/overview.md` and `docs/tech/overview.md`: agent lists.
- `docs/tech/hooks.md`: the "owns the status hooks for …" sentence.
- `docs/reference/agent-session-metadata.md`: the agent list in the intro, and the turn-start
  list if the agent's turn event is new. Its per-agent slot tables need research into which
  fields the agent sends.
- If you added event names to `HookEventMapper`, the wake rules in `docs/tech/hooks.md`,
  `docs/tech/hook-server.md` (Backburner Protection) and `docs/tech/session-management.md`
  (backburner handling).
- `site/index.html`: both meta descriptions, the JSON-LD description, the "Open your sessions"
  copy, the Coding agents compat grid, and the footer platform line.

No per-agent tech doc is needed — that was for bespoke bridges; hooklinesinker-backed agents
share `docs/tech/hooks.md`.

### Verify

`just build ci.xcconfig`, `build-for-testing`, `just lint`, `just format`; the user runs
`just test` (sandboxed sessions cannot). Do **not** run `just run`. Do **not** commit unless
the user says to — they control git.

## Path B: agent not yet in hooklinesinker

The capability research lives there now, not here. In the hooklinesinker repo:

1. **Capability check first** (the lesson this skill exists for — Antigravity was fully built
   before anyone noticed it lacks session start/end events). From the agent's official docs,
   inventory every hook event and map it onto the five phases plus create/remove. Present the
   matrix — every GAP named — and get user sign-off **before writing code**. Watch for: events
   that fire per-model-call vs per-turn; events whose hook must return a control response (do
   not register those unless needed); timeout units (seconds vs milliseconds differ across
   agents); config formats where a bad write disables everything (Kimi's TOML).
2. Implement there: protocol `Agent` variant, normalize table, hook installer, process-ancestry
   matching (mind node-shim process names — verify against a live process, not docs), fixtures
   and tests. hooklinesinker's own README and `docs/design/` describe the constraints (register
   only mapped events; raw input never persisted or forwarded).
3. Ship/bundle the new hooklinesinker version, then run Path A here.

## Troubleshooting

### The agent's docs don't clearly describe its hook events
Do not guess. Mark unknown rows "unverified" at the sign-off; treat unconfirmed core events
(session lifecycle, idle/working) as GAPs until proven otherwise.

### A capability gap is found mid-implementation
Stop, update the matrix, re-run the sign-off. A gap found mid-build is the failure mode this
skill exists to prevent.

### Sessions never appear for the new agent
Check `hooklinesinker sessions --json` directly. If records exist there but not in Juggler,
the bug is Juggler-side (decode/display). If no records exist, it is hooklinesinker-side —
commonly process-ancestry matching (the agent's OS-level process name differs from its command
name; Kimi retitles itself `kimi-code`).

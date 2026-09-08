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

No notify script, no installer, no `HookEventMapper` entry, no `AppStorageKeys` flag (only
opt-in agents — Codex, Antigravity — have one), no `uninstall.sh` block. The full set:

### Code

| File | Change |
|---|---|
| `juggler/Services/HooklinesinkerClient.swift` | Add the `HooklinesinkerAgent` case. Raw value **must equal the wire name** (kebab-case, from hooklinesinker's `src/protocol.rs`); the argv test over `allCases` then pins it automatically. |
| `juggler/Models/Session.swift` | Add `agentShortName` (2 letters, e.g. `DR`) and `agentDisplayName` cases. |
| `juggler/Views/IntegrationHubView.swift` | Add an `IntegrationCard` + a `<Agent>SetupView` (clone the Droid one), and extend `hasAnyAgent`. |
| `juggler/Views/SettingsView.swift` | Add a `Section` with the install button calling `HooklinesinkerClient.shared.installHooks(agent:)`. |

Quirk hints in the UI: if the agent only reads hooks at startup (Droid does), add the restart
hint under the install button, mirroring the existing Droid/Pi hints.

### Behavior checks

- **Backburner**: `SessionManager` exits backburner only on the literal event name
  `UserPromptSubmit` (`SessionManager.swift`, "Preserve backburner state" comment). Confirm the
  agent's turn-start event is named exactly that in hooklinesinker's normalize table; if not,
  extend the guard.
- **Trust/consent**: hooklinesinker never touches trust state. If the agent has a Codex-style
  trust or feature-flag gate, Juggler must own it — stop and design that with the user.

### Tests

Mirror the existing per-agent tests: decode passthrough in `HookServerTests`
(`newAgentsPassThroughUnchanged` pattern), a removal-path case in `IntegrationTests` if the
agent's end event differs from the others. The `allCases` argv test covers the wire name for
free.

### Docs sweep (easy to forget — grep for an existing agent name to find every list)

- `README.md`: intro line, badge row, "Open your sessions" step, **Coding agents** line
  (include a minimum agent version if hooklinesinker documents one).
- `docs/overview.md` and `docs/tech/overview.md`: agent lists.
- `docs/tech/hooks.md`: the "owns the status hooks for …" sentence.
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

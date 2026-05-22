---
name: integrate-coding-agent
description: Methodical workflow for adding a new coding-agent integration (a hooks/plugin bridge) to Juggler. Use when adding support for a new coding agent or CLI — e.g. "integrate the Foo CLI", "add support for a new agent", "build a new agent bridge", "track a new agent's sessions". Runs an up-front capability check so integration gaps surface before any code is written.
---

# Integrate Coding Agent

## Overview

Juggler tracks coding-agent sessions by receiving hook events and mapping them to session states (`idle`, `working`, `permission`, `compacting`, plus session create/remove). Adding an agent means building a "bridge": a notify script, an installer, an event mapping, UI, and docs.

**Why this skill exists:** a past integration (Antigravity) was fully built before anyone noticed the agent has *no session-start and no session-end events* — a capability gap that reshaped what the integration could do, discovered at the very end. This skill front-loads a prerequisites check so gaps are surfaced and signed off **before** design and code.

Do the phases in order. **Do not skip Phase 1, and do not start Phase 2 until the user has signed off on the capability matrix.**

## Phase 1: Prerequisites & Capability Check (MANDATORY — before any design or code)

Research the agent from its official documentation. Prefer reading the actual docs over assumptions — if the docs are ambiguous or missing, say so explicitly rather than guessing. Produce the capability matrix in 1d and get sign-off in 1e.

### 1a. Integration mechanism

- Does the agent expose a hooks / plugin / event system at all? If not → stop; integration is not possible without one.
- Config file: exact path, format (JSON / TOML / etc.), and schema shape.
- Is config global, per-project, or both? Juggler installs globally.
- Minimum agent version that supports the mechanism.
- Is the mechanism stable or experimental/changing? Note the doc date.

### 1b. Event inventory — the critical part

List **every** event the agent fires: name, when it fires, and the payload fields it carries. Then answer each of these explicitly — a "no" is a finding, not a footnote:

- **Session start.** Is there an event when a conversation/session begins? Critically: does it fire at *launch* of the agent, or only at the *first prompt*? (Claude Code: at start. Codex: at first prompt. Antigravity: no start event at all.)
- **Session end.** Is there an event when the session closes/terminates? (Claude Code: `SessionEnd`. Codex / Antigravity: none — Juggler removes the session via terminal-bridge cleanup on window close instead.)
- **Working / idle transitions.** Which events mark the agent starting work and finishing a turn? Beware events that fire per-*model-call* or per-*tool* vs. per-*turn* — a turn can contain many model calls.
- **Permission.** Is there an event when the agent pauses for user approval? If not, the `permission` state is unavailable for this agent.
- **Compaction.** Is there a context-compaction event? If not, `compacting` is unused.

### 1c. Hook execution contract

- **stdin** — format (likely JSON); the field name for the session/conversation id; field-name casing (snake_case vs camelCase).
- **stdout** — does the agent *read* the hook's stdout? Does any event **require** a specific response (a `decision` / control message)? An event whose hook must return a value can **break the agent** if the hook misbehaves — prefer not to register such events unless needed, and document the exact required output.
- **Timeout** — unit (seconds vs milliseconds — they differ across agents) and default.
- **Sync/async** — does the hook block the agent loop?
- **Trust gate / feature flag / approval** — any step the user (or the installer) must perform before hooks run (Codex has both a feature flag and a per-hook trust record; Antigravity has neither).

### 1d. Capability matrix

Map the agent's events onto Juggler's session model. For each row, name the driving event or write **GAP**.

| Juggler need | Agent event | Notes |
|---|---|---|
| session create | ? | which event first reveals a new session, and when does it fire |
| `idle` | ? | |
| `working` | ? | |
| `permission` | ? | GAP is common |
| `compacting` | ? | GAP is common |
| session remove | ? | GAP → fall back to terminal-bridge cleanup |

Also record: config path, schema, timeout unit, required-response events, trust/flag steps, min version.

### 1e. Go / No-Go checkpoint

Present the capability matrix and **every GAP** to the user. State plainly what Juggler will and will not be able to do for this agent — e.g. "no fresh-`idle` state when a window opens; the session first appears as `working` on the first prompt", or "sessions are removed only when the terminal window closes". Get explicit user sign-off before continuing. This checkpoint is the whole point of the skill — do not skip it.

## Phase 2: Design

After sign-off, write a short design doc at `docs/superpowers/specs/` (or follow the user's preference). Decide:

- Agent string (the `agent` field in the unified payload), `agentShortName`, AppStorage key.
- **Which events to register** — register only the events you actually map. Every extra registered event is surface area and risk; required-response events especially.
- The event → `MappedAction` mapping.
- Installer model: which existing bridge it most resembles.

The existing bridges are the reference — read them before designing:
- **Codex** (`CodexHooksInstaller.swift`, `codex-notify.sh`, `mapCodex`) — hooks with a feature flag + trust gate.
- **Antigravity** (`AntigravityHooksInstaller.swift`, `antigravity-notify.sh`, `mapAntigravity`) — hooks, no trust gate, minimal 2-event registration.
- **OpenCode** (`OpenCodePluginInstaller.swift`) — a plugin rather than shell hooks.

## Phase 3: Implementation

Mirror the closest existing bridge. The full file set for a hooks-based agent:

| File | Change |
|---|---|
| `juggler/Resources/<agent>-hooks/<agent>-notify.sh` | New bash hook script — clone `codex-notify.sh`/`antigravity-notify.sh`; change the `agent` field, stdin field extraction, and stdout per the contract from 1c. |
| `juggler/Services/<Agent>HooksInstaller.swift` | New installer — model on `AntigravityHooksInstaller.swift` (simple) or `CodexHooksInstaller.swift` (flag + trust). |
| `juggler/Views/<Agent>SetupController.swift` | New `@MainActor @Observable` controller. |
| `juggler/Models/HookEventMapper.swift` | Add `map<Agent>` + a dispatch `case` in `map(event:agent:)`. |
| `juggler/Models/Session.swift` | Add the `agentShortName` case. |
| `juggler/Models/AppStorageKeys.swift` | Add `<agent>Enabled`. |
| `juggler/Views/IntegrationHubView.swift` | Add an `IntegrationCard` and a `<Agent>SetupView`. |
| `juggler/Views/SettingsView.swift` | Add a `Section`. |
| `juggler/Managers/SessionManager.swift` | If the agent has a user-reengagement event, add it to the backburner-exit guard. |
| `juggler/Resources/hooks/uninstall.sh` | Add a cleanup block. |
| Tests | `HookEventMapperTests`, new `<Agent>HooksInstallerTests`, `HookServerTests`, `IntegrationTests`, `BundleResourcesTests`. |
| Docs | New `docs/tech/<agent>-hooks.md`; update `docs/tech/hook-server.md`, `docs/tech/overview.md`, `docs/overview.md`, `CLAUDE.md`, `README.md`, `site/index.html`. |

Rules: run `just build` and `just test` after each task. Do **not** run `just run` (the user tests the app). Do **not** commit — the user controls git.

## Phase 4: Verify

- `just build` clean, `just test` all green, `just lint` clean.
- `grep -ri <oldname>` to confirm no leftover identifiers (path literals for the agent's config dir are fine).
- Documented quirks in `docs/tech/<agent>-hooks.md` match the capability matrix from Phase 1.
- Hand off for a manual smoke test: install via Integration Hub, run the agent, confirm sessions appear and transition; `just reset-integration` removes everything and is idempotent.

## Examples

### Example: "Let's integrate the Foo CLI"

1. **Phase 1** — Research Foo's hook docs. Inventory events. Discover Foo has `SessionOpen`, `SessionClose`, `TurnStart`, `TurnEnd`, `ToolCall`. Fill the matrix: session create→`SessionOpen`, idle→`TurnEnd`, working→`TurnStart`, permission→GAP, compacting→GAP, session remove→`SessionClose`. Present to the user: "Foo has full lifecycle but no permission or compaction events — those two states will be unused. OK to proceed?"
2. After sign-off → **Phase 2** design doc.
3. **Phase 3** — clone the Antigravity bridge file set, adapt.
4. **Phase 4** — green build/tests, hand off for smoke test.

### Example: capability gap caught early

User: "Add support for Bar CLI." Phase 1 research finds Bar's only hook is `OnToolUse`. The matrix is almost all GAPs: no session create, no idle/working turn boundary, no removal. The Go/No-Go checkpoint surfaces this: "Bar exposes a single tool-use hook — Juggler could only ever show a session flicker to `working` on tool calls, with no reliable `idle`. This integration would be low-value. Recommend not proceeding." The user decides before any code is written.

## Troubleshooting

### The agent's docs don't clearly describe the hook events

**Cause:** New or sparsely documented agent.
**Solution:** Do not guess in the capability matrix. Mark the unknown rows as "unverified" and say so at the Go/No-Go checkpoint. If a core event (session lifecycle, idle/working) can't be confirmed, treat that as a GAP until proven otherwise.

### A capability gap is found mid-implementation despite Phase 1

**Cause:** The event inventory in 1b missed an event, or an event behaves differently than documented.
**Solution:** Stop. Return to Phase 1, update the capability matrix, and re-run the Go/No-Go checkpoint with the user before continuing. A gap found mid-build is exactly the failure mode this skill prevents — do not paper over it.

### The agent has an event whose hook must return a control response

**Cause:** Some agents (e.g. Antigravity's `PreToolUse`/`Stop`) read hook stdout and act on a required `decision` field — a misbehaving hook can block tool calls or trap the agent.
**Solution:** Avoid registering such events unless their state is genuinely needed. If you must, document the exact required stdout and make the notify script emit it unconditionally and first. Prefer events with no required response.

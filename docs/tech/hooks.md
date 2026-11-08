# Claude Code Hooks

Juggler learns what Claude Code is doing from **hooklinesinker**, a small shared binary that
owns the status hooks for Claude Code, Codex, OpenCode, Pi, Factory Droid, Qwen Code and Kimi Code. Juggler ships it inside the app
bundle — there is **no separate Brew (or npm, or pip) dependency to install**. Antigravity is
the one agent still on Juggler's own hooks; see [Antigravity Hooks](antigravity-hooks.md).

Per-agent specifics: [OpenCode Plugin](opencode-plugin.md), [Codex Hooks](codex-hooks.md),
[Pi Extension](pi-extension.md).

## Installation

`HooklinesinkerClient` (`Services/HooklinesinkerClient.swift`) runs the bundled binary:

1. At launch, `install --consumer juggler --sink http://127.0.0.1:<hookPort>/hook` registers
   Juggler as a consumer and promotes the binary to
   `~/.local/share/hooklinesinker/bin/hooklinesinker` (`$XDG_DATA_HOME` honored).
2. The Integration Hub's per-agent buttons run `hooks install --agent claude`, which writes
   the hook entries into `~/.claude/settings.json`.
3. `hooks status --agent claude --json` is what the UI's Installed/Not Installed indicator
   and `IntegrationSync`'s drift check read.

Everything after step 1 runs the **promoted** binary, because that is the path the installed
hook commands point at. The bundle copy lives at `Juggler.app/Contents/MacOS/hooklinesinker`
(`just build` compiles and stages the pinned source for this Mac before Xcode embeds and signs it).
An already installed, newer protocol-compatible version stays active. App startup needs no
download; see [release packaging](release.md) for the build-time source and version pins.

The hooks call `hooklinesinker ingest --agent claude --event <Event>`. No script is copied into
`~/.claude/hooks/juggler/` any more, and the app ships no `notify.sh`.

## Payload contract

The hook writes a protocol-1 status record; hooklinesinker POSTs it to Juggler's sink as it
happens. `Models/HooklinesinkerStatus.swift` decodes it, and `HookServer.routeRequest` tries
that decode **first** for `/hook` bodies, falling back to the legacy `UnifiedHookPayload`
(which is what Antigravity still sends).

```json
{
  "protocol": 1,
  "bindingId": "…",
  "agent": "claude",
  "event": "UserPromptSubmit",
  "phase": "working",
  "running": true,
  "observedAt": "2026-09-04T00:00:00Z",
  "session": { "id": "…", "cwd": "/path", "transcriptPath": "…", "title": "…", "model": "…", "effort": "…", "permissionMode": "…" },
  "process": { "pid": 42, "startedAt": "…", "host": "…" },
  "terminal": { "sessionId": "w0t0p0:UUID", "terminalType": "iterm2", "kittyListenOn": null, "kittyPid": null },
  "tmux": { "pane": "%0", "sessionName": "work" },
  "git": { "branch": "main", "repo": "app" },
  "remoteHost": null,
  "activity": { "tool": "Bash", "subagents": 0, "contextPercent": 42, "turns": 3 }
}
```

Notes that matter when reading Juggler's code:

- `cwd` sits on `session`, not on `terminal` — the opposite of the legacy payload.
- The wire agent is `claude`; `HooklinesinkerStatus.jugglerAgent` maps it to Juggler's
  long-standing `claude-code`, so stats keys and display names are unchanged.
- `phase` is the state directly (`idle`/`working`/`permission`/`compacting`), so the v1 path
  never touches `HookEventMapper`. An unrecognized phase decodes as `unknown` and is logged and
  ignored rather than failing the record.
- Sessions are keyed by `compositeSessionID` = `terminalSessionID[:tmuxPane]`, rebuilt from
  `terminal`/`tmux`. `bindingId` is hooklinesinker's own key and is what startup hydration
  dedupes on.
- `running: false` removes the session, guarded by the stale-thread check below.
- A status with a tmux pane but no `terminal` removes that session's row in that pane:
  hooklinesinker withholds the terminal once the pane's tmux session has no attached client,
  because the inherited terminal variables name whichever tab started the tmux server. With no
  matching row, it falls through to the once-per-source empty-terminal warning, since tmux
  inside a terminal hooklinesinker cannot identify looks the same.

- `session.title`, `model`, `effort`, `permissionMode` and `activity` are optional session details.
  `HooklinesinkerStatus` decodes each leniently (a wrong-typed value becomes absent, `subagents` and
  `turns` default to 0, `contextPercent` is clamped to 0-100), `sessionDetails` maps them to
  `SessionDetails`, and `handleStatus` passes them to `SessionManager.addOrUpdateSession` as a
  `DetailsChange.replace`. `SessionDetails.replaced(by:)`
  replaces the stored details wholesale, because hooklinesinker already merged them with its stored
  record, but keeps the previous process start time when the record has none and drops a record
  whose `observedAt` is older than the one held. Records without a session ID do not update
  details. Which agents fill which fields is in
  [Agent Session Metadata in Hooks](../reference/agent-session-metadata.md); the merge rules are in
  hooklinesinker's `docs/status-lifecycle.md`.
- Offline backburner wake evidence retains `activity.turns` separately as `reportedTurns`: only an explicitly
  supplied nonnegative integer qualifies, never the display's default zero. See
  [backburner handling](session-management.md#backburner-handling).
- The Turns slot shows `activity.turns`, hooklinesinker's per-binding count of turn starts,
  whenever the record carries `activity`. Juggler still keeps its own `Session.turnCount`, which
  the slot falls back to for Antigravity and for records without `activity`:
  `SessionManager.isNewTurn` counts a turn-start event (`UserPromptSubmit`, `TurnStarted`,
  `agent_start`, `PreInvocation`) that moves a row from `idle` to `working` or creates it
  `working`, and for a backburnered row only `UserPromptSubmit`. Hydration replays do not count.
  See [Agent Session Metadata in Hooks](../reference/agent-session-metadata.md#turns-and-run-time).
- A record can arrive with the same `phase` as the row already has, for example a `child:` or
  `resend:` event that only changes `activity`. `handleStatus` compares the row's state before and
  after the update and sends the idle or permission notification only when the state changed,
  so a repeated or activity-only record never notifies again.

Terminal, tmux, git and SSH detection all happen inside hooklinesinker now; Juggler no longer
has a shell script reading `$ITERM_SESSION_ID` and friends for these agents.

### Hydration at launch

`JugglerApp` starts the hook server, then calls `sessions --json` once and replays every
`running` record through the same `handleStatus` path HTTP uses. That is what makes sessions
which started before Juggler launched appear. Records whose binding already arrived live in
that startup window are skipped, so nothing is doubled and a session that ended between the
snapshot and the replay is not resurrected.

Replay restores conversation-scoped Hide/backburner after stable identity is available. Hidden rows still hydrate
and update; list filtering happens in Juggler. Backburner wakes only with the newer evidence described in
[session management](session-management.md#backburner-handling); ambiguous snapshots remain shelved.

Records the user removed are skipped too. **Remove** in a row's context menu
(`SessionManager.dismissSession`) hides every hooklinesinker binding the row carried, with the
removal time, in `HiddenBindingStore` (UserDefaults key `hiddenSessionBindings`). Hydration skips
such a binding unless its record's `observedAt` is later than the removal, which catches activity
Juggler missed while it was not running. `observedAt` has whole-second resolution, so activity
missed in the same second as the removal stays hidden until the next event. Any live `running`
status for the binding reveals it and brings the row back, whatever its timestamp. Automatic
removals (terminal closed, session ended, tmux detached) hide nothing.

`HookServer.hydrate(from:)` prunes hidden bindings the snapshot no longer lists, but only when
the snapshot read the whole ledger: no skipped records and no problems other than sink, ingest
or sweep entries from the health log. A ledger that could not be read comes back as an empty
list with a problem, and pruning on it would bring every dismissed row back at the next launch.

Stale-binding suppression lives in Juggler rather than in hooklinesinker because the ledger is shared: deleting a
binding's record there would hide the session from every consumer, and the next hook would
recreate it anyway.

Remove/`HiddenBindingStore` is independent of durable Hide/`SessionDispositionStore`. New activity clears a
binding's removal suppression but does not unhide its conversation. The durable disposition follows
`(agent, agentSessionID)`, including another binding or pane for that same conversation.

### Reset Sessions

Settings → General → Reset Sessions runs `sessions reset --json` through
`HooklinesinkerClient.resetSessions()`, then `SessionManager.completeSessionReset()` clears the rows,
focus, cycling state, stale-binding suppression and all stored hidden/backburner dispositions after committing in-progress busy time
(`SessionReset.run`). hooklinesinker sends a `swept` event only for dead sessions and nothing
for live ones, so clearing the rows is Juggler's job. If the command exits nonzero, Juggler clears nothing and shows its stderr: rows
cleared while the ledger kept their records would come back at the next launch. A reset that
removed some records before failing on others leaves the rows of the removed ones until their
next event. The reset wipes the local ledger shared with every hooklinesinker consumer; sessions
on SSH hosts keep their remote ledgers and reappear with their next event.

Conversation notes and accumulated busy totals survive. The local reset happens only after the CLI succeeds;
a failed reset leaves rows, notes and dispositions unchanged locally, even if the shared CLI partly changed its ledger.

`sessions reset` first ships in a hooklinesinker release after 1.1.0. A Juggler build pinned to
1.1.0 shows the CLI's usage error instead, so the pin has to be bumped
(`just update-hooklinesinker`) before a Juggler release that includes Reset Sessions.

### HookServer constraints

- Port: `7483` (overridable via `$JUGGLER_PORT`). The sink Juggler registers uses the same
  source `HookServer` binds to, so a test instance on another port points at itself.
- Max request size: **1 MB**.

## Hook Events

Claude Code fires these events; hooklinesinker registers all of them except `SubagentStop`.

| Event | When | Resulting phase |
|-------|------|-----------------|
| `SessionStart` | Session begins | `idle` |
| `UserPromptSubmit` | User sends prompt | `working` |
| `PreToolUse` | Before tool execution | `working` |
| `PostToolUse` | After tool execution | `working` |
| `PostToolUseFailure` | Tool failed | `working` |
| `SubagentStart` | Task agent spawned | `working` |
| `PermissionRequest` | Needs permission | `permission` |
| `PreCompact` | Context compaction | `compacting` |
| `Stop` | Agent finished normally | `idle` |
| `StopFailure` | Turn ended with an API error | `idle` |
| `SessionEnd` | Session terminated | *(removes the session)* |

## Known Quirks

### SubagentStop Fires After Stop

When Claude Code uses subagents (Task tool), the event sequence is:

**Expected:**
```
SubagentStart → [work] → SubagentStop → Stop
```

**Actual:**
```
SubagentStart → [work] → Stop → SubagentStop (5-10 seconds later)
```

The `SubagentStop` event fires **asynchronously after** the main `Stop` event, because subagent
cleanup happens in a background process.

**Impact:** If `SubagentStop` mapped to working state, it would overwrite the idle state from
`Stop`, making sessions appear stuck.

**Solution:** `SubagentStop` is not registered at all. The `Stop` event correctly indicates when
the session becomes idle.

### Stop Does Not Fire on API Errors

Claude Code fires `Stop` only on normal turn completion. On API errors (overloaded, rate limit,
authentication, billing, server, invalid request) it fires a separate `StopFailure` event
instead. User interrupts (ESC) and CLI crashes fire neither.

**Impact:** Without hooking `StopFailure`, sessions hit by API errors would stay stuck in
`working` forever.

**Solution:** Both `Stop` and `StopFailure` are registered and map to `idle`. ESC interrupts and
crashes are still unrecoverable from the hook layer.

### A stale SessionEnd must not remove the live session

Sessions are keyed by terminal pane, so `HookServer` compares the record's `session.id` against
the row's before removing it; a mismatch is ignored. This is what keeps an abandoned thread's
late `SessionEnd` from killing the session that replaced it in the same pane.

### Backburner State Persistence

Backburner intent persists by conversation identity. Hooks keep metadata current while preserving the shelved state;
live prompts or explicit Reactivate wake it (with an awaiting-user working-event exception for Antigravity).
Launch snapshots require strictly newer activity proof. See [backburner handling](session-management.md#backburner-handling)
for the evidence rules and invalid-count cases.

## Configuration

The entries hooklinesinker writes into `~/.claude/settings.json` look like this:

```json
{
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "~/.local/share/hooklinesinker/bin/hooklinesinker ingest --agent claude --event SessionStart", "timeout": 5}]}],
    "PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "… ingest --agent claude --event PreToolUse", "timeout": 5}]}]
  }
}
```

The installer reconciles **its own** generated group and preserves unrelated settings and hooks;
a structurally unfamiliar `settings.json` is reported as `unsupported` and left alone rather than
rewritten. Read the current state with `hooklinesinker hooks status --agent claude --json`.

## Debugging

```bash
hls=~/.local/share/hooklinesinker/bin/hooklinesinker

$hls doctor                                  # version, hook drift, ledger faults
$hls sessions --json                         # what Juggler hydrates from
$hls sessions reset                         # what Reset Sessions runs (clears the ledger)
$hls hooks status --agent claude --json      # registration + the exact commands
$hls consumers --json                        # who else shares these hooks

# Test the sink directly (the legacy shape Antigravity still uses)
curl http://localhost:7483/hook -X POST -d '{"agent":"test","event":"ping"}'
```

The in-app log viewer (Settings → Logs) shows what the hook server received.

## Uninstall / Reset

Settings → Reset integrations, `just reset-integration`, `just reset-all`, and Homebrew zap
all run `Resources/hooks/uninstall.sh`, which delegates to `integration_cleanup.py`:

1. `hooks status --agent codex --json`, to capture the trust keys **before** anything removes
   hooks (the keys are built from the group indexes hooks.json currently holds).
2. `hooklinesinker uninstall --consumer juggler` removes Juggler's registration, and
   removes the shared hooks and the promoted binary only if Juggler was the **last** consumer.
   Another tool (e.g. ringleader) still using them keeps them installed.
3. A fresh status read confirms whether the Codex hooks were removed. Only then does
   `codex_config_cleanup.py` remove matching canonical trust entries from `config.toml`.
   Remaining consumers keep their trust; a failed or ambiguous status read preserves it.
4. The cleanup script clears everything else Juggler owns: the
   Kitty watcher, Antigravity hooks, the Automation (Apple Events) permission via `tccutil`,
   and — through `codex_config_cleanup.py` — pre-migration trust entries written over the old
   `notify.sh` command.

Shared configuration writes preserve symlinks and file permissions. Invalid JSON reports a failure and preserves that integration's files and recovery backup; cleanup continues for the other integrations and exits nonzero. Successful cleanup deletes stale Juggler recovery backups. Shared tmux settings remain.

See [Homebrew distribution](homebrew.md) for install, upgrade, and zap behavior. `just test-packaging` exercises cleanup against temporary directories without launching Juggler or resetting system permissions.

---

[← Back to Tech Overview](overview.md)

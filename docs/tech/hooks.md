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
  "session": { "id": "…", "cwd": "/path", "transcriptPath": "…" },
  "process": { "pid": 42, "startedAt": "…", "host": "…" },
  "terminal": { "sessionId": "w0t0p0:UUID", "terminalType": "iterm2", "kittyListenOn": null, "kittyPid": null },
  "tmux": { "pane": "%0", "sessionName": "work" },
  "git": { "branch": "main", "repo": "app" },
  "remoteHost": null
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

Terminal, tmux, git and SSH detection all happen inside hooklinesinker now; Juggler no longer
has a shell script reading `$ITERM_SESSION_ID` and friends for these agents.

### Hydration at launch

`JugglerApp` starts the hook server, then calls `sessions --json` once and replays every
`running` record through the same `handleStatus` path HTTP uses. That is what makes sessions
which started before Juggler launched appear. Records whose binding already arrived live in
that startup window are skipped, so nothing is doubled and a session that ended between the
snapshot and the replay is not resurrected.

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

When a session is backburnered:

- Most events are ignored (state preserved)
- Only a prompt submission exits backburner
- This prevents working sessions from being unintentionally un-backburnered

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

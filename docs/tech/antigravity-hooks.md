# Antigravity Hooks

Juggler integrates with the [Antigravity CLI](https://antigravity.google/docs/cli/features) (`agy`, Google's terminal coding agent) via shell hooks — the same model as Claude Code and Codex, but simpler: **no feature flag and no trust gate.** Antigravity picks up a newly registered hook on its next run.

Requires Antigravity CLI ≥ 1.0.8 (the version that fixed the global hooks path to `~/.gemini/config/hooks.json`).

## Installation

Antigravity setup is a **single step** (one button in onboarding's Integration Hub and in Settings → Integration):

1. **Install Hooks**: copies the bundled script to `~/.gemini/hooks/juggler/notify.sh` (`chmod 755`) and registers the two events under a top-level `"juggler"` key in `~/.gemini/config/hooks.json`.

`AntigravityHooksInstaller` (`Services/AntigravityHooksInstaller.swift`) implements it (wired via `AntigravitySetupController`). The merge backs up an existing `hooks.json` once to `<path>.juggler-backup` before the first write.

**Files involved:**
- `~/.gemini/hooks/juggler/notify.sh` — the hook script (bundled in the app as `Resources/antigravity-hooks/antigravity-notify.sh`).
- `~/.gemini/config/hooks.json` — event → hook registration, keyed by hook name.

`~/.gemini/config/hooks.json` is **shared** with the Antigravity 2.0 IDE. The Juggler hook fires for IDE sessions too, but those carry no terminal env vars, so the notify script sends an empty `terminal.sessionId` and `HookServer` drops the event (its empty-`terminalSessionID` guard) — IDE sessions never appear in Juggler.

## Hook Script

**File:** `Resources/antigravity-hooks/antigravity-notify.sh` (installed as `notify.sh`)

Structurally identical to the Codex script (`Resources/codex-hooks/codex-notify.sh`): event name as `$1`, hook JSON on stdin, detects terminal type / tmux / git, builds the unified payload via a quoted Python heredoc, and fire-and-forgets it to `curl`. Two differences matter:

1. **camelCase input → snake_case payload.** Antigravity's stdin uses camelCase; the script normalizes `conversationId` → `session_id` and `transcriptPath` → `transcript_path`, so the HookServer's shared decoding path is unchanged.
1. **cwd comes from `workspacePaths`, not `$PWD`.** Antigravity runs the hook from its own config dir (`~/.gemini/config`), so `$PWD` is wrong. The script reads `workspacePaths[0]` from stdin and uses it for both the reported cwd and git branch/repo detection (falling back to `$PWD` if absent). Without this, sessions show `~/.gemini/config` and never resolve a git branch.
2. **stdout response (the critical one).** Antigravity *reads* the hook's stdout. The script emits it **unconditionally**, independent of the POST — so Juggler being down never blocks or traps the agent:
   - `Stop` → `{"decision":"stop"}`. Any value other than `"continue"` allows the stop; emitting `"continue"` would trap the agent back into its execution loop.
   - `PreInvocation` → `{}` (output is optional).

   The best-effort POST is bounded (`--connect-timeout 1 --max-time 2 || true`), so the script always reaches the `echo` within the hook timeout.

The payload's `agent` field is `"antigravity"`.

```json
{
  "agent": "antigravity",
  "event": "PreInvocation",
  "hookInput": { "session_id": "<conversationId>", "transcript_path": "..." },
  "terminal": { "sessionId": "w0t0p0:UUID", "cwd": "/path", "terminalType": "iterm2" },
  "git": { "branch": "main", "repo": "app" }
}
```

See [Claude Code Hooks](hooks.md) for the full payload contract — it is shared.

## Hook Events

Antigravity's CLI exposes five events; Juggler registers **only two**. `PreToolUse`/`PostToolUse`/`PostInvocation` are deliberately skipped — `PreToolUse` requires a `decision` response and can block every tool call if it misbehaves, and the others are per-tool / per-model-call noise rather than turn boundaries.

| Event | Mapped State |
|-------|--------------|
| `PreInvocation` | `working` |
| `Stop` | `idle` |

Mapping lives in `HookEventMapper.mapAntigravity`. Event names are matched case-sensitively; everything else maps to `.ignore`.

## hooks.json Registration

`mergeHooksJSON` sets a top-level `"juggler"` key, preserving every other key. `PreInvocation`/`Stop` take a **flat handler list** — not the `{matcher, hooks:[…]}` wrapper `PreToolUse` uses:

```json
{
  "juggler": {
    "PreInvocation": [
      { "type": "command", "command": "~/.gemini/hooks/juggler/notify.sh PreInvocation", "timeout": 5 }
    ],
    "Stop": [
      { "type": "command", "command": "~/.gemini/hooks/juggler/notify.sh Stop", "timeout": 5 }
    ]
  }
}
```

Re-merge replaces the `"juggler"` key wholesale, so reinstalls don't duplicate. Because Juggler owns its own top-level key, other tools' hooks (keyed by their own names) are never touched.

## Reset

`uninstall.sh` (run by `just reset-integration`) reverts Antigravity:
- `rm -rf ~/.gemini/hooks/juggler/`.
- Deletes the top-level `"juggler"` key from `~/.gemini/config/hooks.json` (removes the file if it becomes empty); deletes the stale `hooks.json.juggler-backup`.

## Known Quirks

### No session-start or session-end event

Antigravity fires no event when a conversation begins or ends. A session therefore first appears in Juggler as **`working`** on its first `PreInvocation` (not fresh-`idle` like Claude Code, nor `idle`-on-first-prompt like Codex). With no session-end event, a stopped session lingers until its terminal window closes (terminal-bridge cleanup removes it then).

### No permission or compaction state

There is no event for "agent blocked waiting for user approval" and none for context compaction, so the `permission` and `compacting` states are **never produced** for Antigravity sessions.

### `Stop` is per-turn and requires a response

`Stop` fires when the execution loop terminates — i.e. at the end of a turn (`terminationReason: "model_stop"`), not at session close. Its hook **must** return a `decision`; the notify script always emits an allow (`{"decision":"stop"}`). See the Hook Script section.

### Backburner auto-reactivation is idle-origin only

Antigravity has no `UserPromptSubmit` (the user-action event other agents use to exit backburner). Its only "user re-engaged" proxy is a `working` event, which fires on every model call within a turn. So a backburnered Antigravity session is auto-reactivated on its next `working` event **only if it was idle when backburnered** (a resume); one shelved while working stays put until it goes idle and is explicitly reactivated. This is driven by `Session.wasAwaitingUserBeforeBackburner`, set in `SessionManager.applyStateChange`. See [the design spec](../superpowers/specs/antigravity-integration.md).

---

[← Back to Tech Overview](overview.md)

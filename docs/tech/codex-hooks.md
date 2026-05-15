# Codex Hooks

Juggler integrates with [Codex CLI](https://github.com/openai/codex) via shell hooks, the same model as Claude Code. The wrinkle is Codex's *hook trust* gate: Codex refuses to run a newly registered hook until the user reviews it in the `/hooks` TUI. Juggler writes the trust record directly so the hooks work without that manual step.

Requires Codex CLI ≥ v0.114.

## Installation

Codex setup is **three separate steps** (three buttons in onboarding's Integration Hub and in Settings → Integration). They are independent and idempotent — run them in order:

1. **Install Hooks** — copies the bundled script to `~/.codex/hooks/juggler/notify.sh` (`chmod 755`) and registers all eight events in `~/.codex/hooks.json`.
2. **Enable Feature Flag** — sets `[features] hooks = true` in `~/.codex/config.toml`. Codex ignores `hooks.json` entirely unless this flag is on.
3. **Enable in Codex** — writes `[hooks.state]` trust records to `config.toml` so the hooks run without the manual `/hooks` review. This bypasses Codex's own trust-enabling flow; the alternative is to skip this step and run `/hooks` inside Codex to approve Juggler's hooks manually.

`CodexHooksInstaller` (`Services/CodexHooksInstaller.swift`) implements all three. Each step that modifies an existing file backs it up once to `<path>.juggler-backup` before the first write.

**Files involved:**
- `~/.codex/hooks/juggler/notify.sh` — the hook script (bundled in the app as `Resources/codex-hooks/codex-notify.sh`).
- `~/.codex/hooks.json` — event → hook registration.
- `~/.codex/config.toml` — feature flag (`[features] hooks`) and trust records (`[hooks.state]`).

## Hook Script

**File:** `Resources/codex-hooks/codex-notify.sh` (installed as `notify.sh`)

Functionally identical to the Claude Code script (`Resources/hooks/notify.sh`): event name as `$1`, hook JSON on stdin, detects terminal type / tmux / git, builds the unified payload via a quoted Python heredoc, and fire-and-forgets it to `curl --connect-timeout 1`. It extracts only `session_id`, `transcript_path`, `tool_name` from stdin to stay under the HookServer's 1 MB request cap.

The only meaningful difference: the payload's `agent` field is `"codex"`.

```json
{
  "agent": "codex",
  "event": "UserPromptSubmit",
  "hookInput": { "session_id": "...", "transcript_path": "...", "tool_name": "Bash" },
  "terminal": { "sessionId": "w0t0p0:UUID", "cwd": "/path", "terminalType": "iterm2" },
  "git": { "branch": "main", "repo": "app" },
  "tmux": { "pane": "%0", "sessionName": "work" }
}
```

See [Claude Code Hooks](hooks.md) for the full payload contract — it is shared.

## Hook Events

Codex fires eight events. There is **no `SessionEnd`** — sessions are removed via terminal-bridge cleanup when the window closes, not by a hook.

| Event | Mapped State |
|-------|--------------|
| `SessionStart` | `idle` |
| `Stop` | `idle` |
| `UserPromptSubmit` | `working` |
| `PreToolUse` | `working` |
| `PostToolUse` | `working` |
| `PostCompact` | `working` |
| `PreCompact` | `compacting` |
| `PermissionRequest` | `permission` |

Mapping lives in `HookEventMapper.mapCodex`. Event names are matched case-sensitively; an unrecognized event maps to `.ignore`.

## hooks.json Registration

`mergeHooksJSON` adds one matcher group per event, each with a single command handler:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "~/.codex/hooks/juggler/notify.sh SessionStart", "timeout": 5 }] }
    ]
  }
}
```

It removes any pre-existing Juggler group (matched by a loose substring match on the command) before re-adding, so reinstalls don't duplicate. A user's own hooks for the same event are left untouched — Juggler's group is simply appended after them.

## Trust Mechanism

Codex stores hook trust in `~/.codex/config.toml`:

```toml
[hooks.state."<hooksJSONPath>:<snake_event>:<groupIndex>:<handlerIndex>"]
trusted_hash = "sha256:<hex>"
```

- **Key** — `<hooksJSONPath>` is the absolute path to `hooks.json`; `<snake_event>` is the event in snake_case (`session_start`, `user_prompt_submit`, …); `<handlerIndex>` is always `0` (Juggler registers a single-handler group per event); `<groupIndex>` is **resolved at install time** from `hooks.json` — it is *not* always `0`. If the user already has their own hook for an event, theirs sits at group 0 and Juggler's lands at group 1.
- **`trusted_hash`** — SHA-256 over Codex's canonical hook fingerprint: sorted-key, compact JSON with slashes unescaped, of `{"event_name":"<snake>","hooks":[{"async":false,"command":"<cmd>","timeout":5,"type":"command"}]}`. `computeTrustedHash` mirrors this exactly. The `timeout` (5s) is part of the hashed identity, so `hookTimeoutSeconds` must stay in sync between the value written to `hooks.json` and the value folded into the hash.

`enableInCodex` rewrites **only** the exact `[hooks.state]` keys it is about to produce — it never prefix-matches. Prefix-matching would delete a user's own trust block: once Juggler moves to group index 1, a `<path>:<event>:0:0` block belongs to the *user*, not to a stale Juggler entry. The one genuine orphan case — Juggler moving from index 1 back to 0, leaving a dead `:1:0` block — is harmless (Codex never computes a key for a group index absent from `hooks.json`), and `uninstall.sh` garbage-collects it on reset.

`isEnabledInCodex` returns true only when config.toml has a matching `trusted_hash` for *every* registered Juggler hook. Any missing/unparseable `hooks.json`, unresolved event, or hash mismatch → false, which is what drives the "Enable in Codex" button's status indicator.

## Reset

`uninstall.sh` (run by `just reset-integration`) fully reverts Codex:
- `rm -rf ~/.codex/hooks/juggler/`.
- If `~/.codex/config.toml.juggler-backup` exists → `mv` it back over `config.toml`. This restores the exact pre-Juggler state (no `[features] hooks`, no `[hooks.state]` blocks) without parsing TOML. If Juggler created `config.toml` from scratch (no backup), it is left alone — the leftover flag/blocks are harmless.
- `~/.codex/hooks.json` is surgically stripped of Juggler's groups (or removed if it becomes empty); the stale `hooks.json.juggler-backup` is deleted.

## Known Quirks

### SessionStart fires at first message, not at launch

Codex does not fire `SessionStart` when the TUI opens — only when the user submits their first prompt. A freshly opened Codex window therefore does not appear in Juggler until the first message. The Session Monitor's empty-state text notes this. There is no `SessionEnd` either, so a stopped Codex session lingers until its terminal window closes (terminal-bridge cleanup removes it then).

### config.toml is hand-edited, not TOML-parsed

`CodexHooksInstaller` does targeted string edits on `config.toml` rather than round-tripping it through a TOML library (Swift has no bundled TOML parser). The helpers (`parseBoolAssignment`, `parseStringAssignment`, `editedTOML`) handle Juggler's known-shape values and tolerate trailing `# comment`s, but are not a general TOML parser. This is why reset prefers restore-from-backup over surgical removal for `config.toml`.

---

[← Back to Tech Overview](overview.md)

# Codex Hooks

Juggler learns what [Codex CLI](https://github.com/openai/codex) is doing through
**hooklinesinker**, the shared status binary the app bundles — no separate Brew dependency. The
wrinkle Codex adds is its *hook trust* gate: Codex refuses to run a newly registered hook until
the user reviews it in the `/hooks` TUI. Trust records are the **host application's** business,
so hooklinesinker never touches `config.toml`; Juggler writes and removes them itself.

Requires Codex CLI ≥ v0.114; `SessionEnd` additionally requires ≥ v0.145 (older builds ignore the unregistered event without rejecting the rest of `hooks.json`).

## Installation

Codex setup is **three separate steps** (three buttons in onboarding's Integration Hub and in Settings → Integration). They are independent and idempotent - run them in order:

1. **Install Hooks**: `hooklinesinker hooks install --agent codex` registers all ten events in
   `~/.codex/hooks.json`, each calling `<promoted binary> ingest --agent codex --event <Event>`.
   Nothing is copied into `~/.codex/hooks/juggler/` any more.
2. **Enable Feature Flag**: sets `[features] hooks = true` in `~/.codex/config.toml`. Codex ignores `hooks.json` entirely unless this flag is on.
3. **Enable in Codex**: writes `[hooks.state]` trust records to `config.toml` so the hooks run without the manual `/hooks` review. This bypasses Codex's own trust-enabling flow; the alternative is to skip this step and run `/hooks` inside Codex to approve the hooks manually.

`CodexSetupController` drives all three. Step 1 goes through `HooklinesinkerClient`; steps 2 and
3 stay in `CodexHooksInstaller` (`Services/CodexHooksInstaller.swift`), which backs an existing
`config.toml` up once to `<path>.juggler-backup` before its first write.

**Files involved:**
- `~/.codex/hooks.json` — event → hook registration, owned by hooklinesinker.
- `~/.codex/config.toml` — feature flag (`[features] hooks`) and trust records (`[hooks.state]`), owned by Juggler.

Remote hosts use `scripts/install-remote.sh`, which downloads and checksum-verifies a
hooklinesinker release and runs step 1 only. Steps 2 and 3 have to be done by hand there — the
script says so — because there is no Juggler app on that machine to compute the trust hashes.

## Payload

The hook writes a protocol-1 status record with `agent: "codex"`; hooklinesinker POSTs it to
Juggler's sink. See [Claude Code Hooks](hooks.md#payload-contract) for the shape — it is shared
by all four agents.

## Hook Events

hooklinesinker registers ten events.

| Event | Mapped State |
|-------|--------------|
| `SessionStart` | `idle` |
| `Stop` | `idle` |
| `Interrupt` | `idle` (session stays live) |
| `UserPromptSubmit` | `working` |
| `PreToolUse` | `working` (`idle` for `request_user_input`) |
| `PostToolUse` | `working` |
| `PostCompact` | `working` |
| `PreCompact` | `compacting` |
| `PermissionRequest` | `permission` (optionally ignored for Auto Review) |
| `SessionEnd` | *(removes the session)* |

Codex emits `Interrupt` when the user cancels a turn. Registering only `Stop` leaves that
session working. Existing installations need **Install Hooks** and trust approval for the new
event through **Enable in Codex** or `/hooks`.

Codex also fires `SubagentStart` and `SubagentStop`, which are not registered.

The mapping now lives in hooklinesinker (`src/normalize.rs`), which puts the resulting `phase`
straight on the wire — the v1 path never reaches `HookEventMapper`. Event and tool names are
matched case-sensitively; an unrecognized event produces no state change. Codex executes
`request_user_input` as a tool and waits inside it for the user's answers, so that specific
`PreToolUse` maps to `idle`; the matching `PostToolUse` maps back to `working` after the user
responds.

Codex does not identify the active reviewer in `PermissionRequest` hook input. The optional **Ignore Codex permission
events** preference therefore suppresses every Codex `PermissionRequest` transition and leaves the session in its
current state. This prevents Auto Review from briefly putting the session in Juggler's permission queue, but also hides
manual permission prompts. Juggler preselects the preference when the top-level `approvals_reviewer = "auto_review"`
setting is present in `~/.codex/config.toml`; profile and command-line overrides are not detected. `request_user_input`
and `Stop` still move the session to `idle` when Codex actually waits for the user.

## hooks.json Registration

hooklinesinker adds one matcher group per event, each with a single command handler:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "~/.local/share/hooklinesinker/bin/hooklinesinker ingest --agent codex --event SessionStart", "timeout": 5 }] }
    ]
  }
}
```

Its own group carries a generated marker, so a reinstall reconciles that group in place rather
than duplicating it. A user's own hooks for the same event are left untouched, and a
structurally unfamiliar `hooks.json` is reported as `unsupported` and not rewritten at all.

Juggler reads the registration back with `hooks status --agent codex --json`, which returns the
config path plus one entry per hook (`event`, `command`, `groupIndex`). Those three values are
exactly what the trust key and hash below are built from — Juggler no longer parses
`hooks.json` itself, so the two can no longer disagree about what was installed.

## Trust Mechanism

Codex stores hook trust in `~/.codex/config.toml`:

```toml
[hooks.state."<hooksJSONPath>:<snake_event>:<groupIndex>:<handlerIndex>"]
trusted_hash = "sha256:<hex>"
```

- **Key**: `<hooksJSONPath>` is the absolute path to `hooks.json`; `<snake_event>` is the event in snake_case (`session_start`, `user_prompt_submit`, …); `<handlerIndex>` is always `0` (hooklinesinker registers a single-handler group per event); `<groupIndex>` is **resolved at install time** from `hooks.json` - it is *not* always `0`. If the user already has their own hook for an event, theirs sits at group 0 and Juggler's lands at group 1.
- **`trusted_hash`**: SHA-256 over Codex's canonical hook fingerprint: sorted-key, compact JSON with slashes unescaped, of `{"event_name":"<snake>","hooks":[{"async":false,"command":"<cmd>","timeout":5,"type":"command"}]}`. `computeTrustedHash` mirrors this exactly, hashing **the command string hooklinesinker reported**, never one Juggler reconstructs. The `timeout` (5s) is part of the hashed identity, so `timeoutSeconds(for:)` must stay in sync with the value hooklinesinker writes into `hooks.json`.

`enableInCodex` rewrites **only** the exact `[hooks.state]` keys it is about to produce - it never prefix-matches. Prefix-matching would delete a user's own trust block: once Juggler moves to group index 1, a `<path>:<event>:0:0` block belongs to the *user*, not to a stale Juggler entry. The one genuine orphan case - Juggler moving from index 1 back to 0, leaving a dead `:1:0` block - is harmless (Codex never computes a key for a group index absent from `hooks.json`).

`enableInCodex` re-reads `hooks status --agent codex --json` first, because an install since the last refresh can have moved the group index the key is built from.

`isEnabledInCodex` returns true only when config.toml has a matching `trusted_hash` for *every* hook hooklinesinker reports. Any missing/unparseable `hooks.json`, unresolved event, or hash mismatch → false, which is what drives the "Enable in Codex" button's status indicator.

## Reset

Settings → Reset integrations, the `just` reset recipes, and Homebrew zap use the same
`integration_cleanup.py` path. Trust keys depend on the current `hooks.json` group indexes:

1. `hooks status --agent codex --json` captures the path and entries **first**.
2. `hooklinesinker uninstall --consumer juggler` removes Juggler's registration; `hooks.json`
   is stripped only if Juggler was the last consumer.
3. A second status read through the preserved versioned binary confirms that those hooks
   are gone. If they remain for another consumer, trust stays intact. Failed or ambiguous
   reads report an error and preserve trust.
4. Once removal is confirmed, `codex_config_cleanup.py` drops only `[hooks.state]` blocks
   matching both a captured key and its canonical hash. A different hash at the same key
   is preserved, along with unrelated settings, symlinks and file permissions.
5. The script clears legacy integrations, including pre-migration trust entries written
   over the old `notify.sh` command.

The global `[features] hooks = true` flag remains. It is harmless without registered/trusted hooks, and Juggler cannot safely distinguish a flag it enabled from one the user now relies on. After successful cleanup, the old recovery snapshot is deleted so a later installation can capture a fresh baseline.

## Known Quirks

### SessionStart fires at first message, not at launch

Codex does not fire `SessionStart` when the TUI opens - only when the user submits their first prompt. A freshly opened Codex window therefore does not appear in Juggler until the first message. The Session Monitor's empty-state text notes this.

Verified against Codex 0.145.0: a TUI left open for 20s with no prompt submitted fires no hook at all, while the same capture path receives `SessionStart`/`UserPromptSubmit`/`Stop` the moment a prompt is sent. The `source: "startup"` field on `SessionStart` describes why the session was created, not when the process launched - Codex creates the session lazily.

### Interrupt and SessionEnd hooks are clamped to 3s

Codex caps `Interrupt` and `SessionEnd` hook timeouts at 3s and computes the trust fingerprint
from the **post-clamp** value. Hashing the usual 5s produces a trust record Codex rejects.
`CodexHooksInstaller.timeoutSeconds(for:)`, the cleanup script, and hooklinesinker's
`CODEX_EVENTS` use 3s for both events; the other eight events use 5s. These values must stay
aligned across both repositories.

The [`Interrupt` payload](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/hooks/src/events/interrupt.rs#L56-L83)
and [timeout normalization](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/hooks/src/engine/discovery.rs#L740-L760)
were checked against Codex 0.153.4 source.

### A stale SessionEnd must not remove the live session

Codex does not fire `SessionEnd` on `/new`, `/clear`, fork, resume, or compaction — those produce a bare `SessionStart` with the corresponding `source`. The abandoned thread still fires its own `SessionEnd` later (idle-unload, ~30 min, or at quit). Sessions are keyed by terminal pane, so `HookServer` compares the hook's `session_id` against the row's before removing; a mismatch is ignored. Agents that send no session id are unaffected.

### Auto-sync refreshes trust, it never grants it

`IntegrationSync` reinstalls Codex hooks when `hooks status` reports `drifted`, but writing a `[hooks.state]` entry is a different act: it bypasses the `/hooks` review Codex asks the user for. So the re-trust is gated on `CodexHooksInstaller.hasExistingTrustEntries`, sampled *before* the reinstall (the re-merge can shift group indices, which are part of the trust key). With an existing matching entry we are refreshing a grant the user already made; with none we re-register and stop, and the setup UI shows "Enable in Codex" as outstanding. The check matches a full key+hash pair rather than prefix-matching the hooks.json path, so a user's own hook registered in the same file is never read as consent.

The feature-flag gate alone was not enough: `features.hooks = true` is setup step 2, while the trust bypass is step 3, so a user who enabled the flag and then chose Codex's own review would have had entries written for them at launch.

### Adding an event is hooklinesinker's job now

Events are registered into `hooks.json` at install time, so adding one does not reach existing
installs on its own. hooklinesinker's own `hooks status` reports `drifted` when a registered
event is missing, and `IntegrationSync` reinstalls on exactly that signal — `missing` means the
user never installed (reinstalling would be uninvited) and `unsupported` means a config shape we
must not rewrite. Adding an event therefore means changing `CODEX_EVENTS` in hooklinesinker, and
keeping `CodexHooksInstaller.agentEvents` in step so trust covers the new entry.

### No Separate Failure Event

Unlike Claude Code (which fires `StopFailure` on API errors instead of `Stop`) and OpenCode (which has a distinct `session.error` bus event), Codex collapses success and error turn endings into the same `Stop` event. The error context lives in the hook payload, not the event name. This means no extra hook is needed to recover from API failures - the existing `Stop` → `idle` mapping covers both paths. User interrupts and CLI crashes still fire no hook on Codex either.

### config.toml is hand-edited, not TOML-parsed

`CodexHooksInstaller` does targeted string edits on `config.toml` rather than round-tripping it through a TOML library (Swift has no bundled TOML parser). A lexical scanner finds statements outside strings and arrays before feature-flag and trust edits. The helpers handle Juggler's known-shape values and trailing `# comment`s; malformed string or bracket boundaries stop the write. This is not a general TOML parser.

Reset removes only complete `[hooks.state]` sections that match current Juggler registrations or Juggler's trusted hashes, preserving the remaining source text. Its scanner recognizes table boundaries outside strings and arrays, including trailing comments, following [TOML's string and comment rules](https://toml.io/en/v1.0.0). This keeps annotated profiles and multiline instructions separate from trust entries. Unterminated strings or unbalanced brackets stop Codex cleanup before any of its files or recovery snapshots are changed. The helper also runs with macOS's Python 3.9, which has no standard-library TOML parser.

---

[← Back to Tech Overview](overview.md)

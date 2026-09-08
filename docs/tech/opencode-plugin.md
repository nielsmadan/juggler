# OpenCode Plugin

Juggler learns what OpenCode is doing through **hooklinesinker**, the shared status binary the
app bundles — no separate Brew dependency. OpenCode has no shell hooks, so hooklinesinker ships
a TypeScript plugin that runs inside the OpenCode process and shells out to the binary.

## Installation

`hooklinesinker hooks install --agent opencode` writes the plugin to
`$OPENCODE_CONFIG_DIR/plugins/hooklinesinker-opencode.ts` (falling back to
`${XDG_CONFIG_HOME:-~/.config}/opencode`), substituting the promoted binary's absolute path into
the template. It removes the pre-migration `juggler-opencode.ts` in the same pass, so an upgraded
install does not report twice.

The plugin source lives in hooklinesinker (`assets/opencode-hooklinesinker.ts`) and is compiled
into the binary with `include_str!`, so Juggler no longer ships a `.txt` copy in its resources —
the Xcode filesystem-synchronized group can no longer misroute it into Compile Sources.

Juggler's onboarding flow and `IntegrationHubView` run the install; the Installed/Not Installed
indicator reads `hooks status --agent opencode --json`. OpenCode loads plugins from that
directory at startup.

## Lifecycle

Unlike Claude Code (stateless hook scripts invoked per event), the OpenCode plugin is a long-lived function. On plugin load it:

1. Captures the OpenCode session id and working directory.
2. Leaves terminal, tmux, git and SSH detection to the binary, which re-reads them per event.
4. Ingests a synthetic `session.created` event immediately.
5. Subscribes to OpenCode events via the returned `event` handler.

The immediate `session.created` post is deliberate: when OpenCode resumes a previous session, the real `session.created` event is not fired, so without this the resumed session would never be seen.

## Tracked Events

Only these events are forwarded:

| OpenCode event | Forwarded as |
|----------------|--------------|
| `session.created` | `session.created` |
| `session.status` (with `properties.status.type`) | `session.status.<type>` - e.g., `session.status.idle`, `session.status.busy`, `session.status.retry` |
| `session.idle` | `session.idle` |
| `session.error` | `session.error` |
| `session.compacted` | `session.compacted` |
| `session.deleted` | `session.deleted` |
| `permission.asked` | `permission.asked` |
| `server.instance.disposed` | `server.instance.disposed` |

All other event types are ignored.

`session.status` is a parent event. The plugin reads `event.properties.status.type` and forwards a synthetic `session.status.<type>` event. If `status.type` is missing, the event is dropped.

`session.idle` and `session.error` are distinct upstream events. Both map to idle so a session does not stay stuck in working after an API/model error.

## Payload

The plugin does not talk to Juggler's HTTP server. It runs
`hooklinesinker ingest --agent opencode --event <event>` and writes
`{"session_id": "...", "cwd": "..."}` to its stdin; the binary enriches that into a protocol-1
status record and POSTs it to Juggler's sink. See
[Claude Code Hooks](hooks.md#payload-contract) for the record shape — it is shared by all four
agents, and terminal/tmux/git/SSH detection now happens in one place instead of four.

`session_id` is extracted from whichever of these is present: `event.properties.sessionID`, `event.properties.info.id`, `event.session_id`, `event.sessionID`.

## Failure Handling

Every ingest is spawned with a kill timer and its failures are swallowed, so a missing, hanging or
erroring binary cannot block OpenCode. hooklinesinker's own delivery to the sink is separately
bounded, and a failed POST becomes a `problems` entry rather than a hook failure.

## Differences from Claude Code Hooks

| | Claude Code | OpenCode |
|---|---|---|
| Integration type | Shell hooks calling `hooklinesinker ingest` | In-process TypeScript plugin calling the same |
| Terminal detection | Re-read from env each invocation | Re-read by the binary each invocation |
| Session create on resume | Fired by Claude Code | Synthesized by plugin on load |
| Event namespace | `SessionStart`, `UserPromptSubmit`, `PreToolUse`, ... | `session.created`, `session.status.*`, `permission.asked`, ... |
| Failure behavior | Hook exits 0 regardless; delivery bounded | Spawn with a kill timer, errors swallowed |

See `docs/tech/hook-server.md` for the event-to-state mapping both agents share.

## Gotchas

- **Resumed sessions need the synthetic `session.created`**: removing the immediate post on plugin load silently breaks session tracking for any resumed OpenCode session.
- **`session.status` without a `type`** is dropped - if OpenCode changes its event shape, the plugin silently stops reporting status updates. hooklinesinker's node harness (`tests/assets_harness.mjs`) pins this behaviour.
- **The plugin embeds an absolute binary path**: it is generated at install time from the promoted binary. Moving `~/.local/share/hooklinesinker` breaks it; reinstall rather than editing the file.
- **The sink URL is registered, not embedded**: Juggler's port comes from `install --consumer juggler --sink ...`, so a test instance on another port re-registers rather than editing the plugin.

---

[← Back to Tech Overview](overview.md)

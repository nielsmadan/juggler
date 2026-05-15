# OpenCode Plugin

Juggler integrates with OpenCode via a TypeScript plugin rather than shell hooks. The plugin runs inside the OpenCode process and posts session events to Juggler's HTTP server.

## Installation

The plugin is installed to `~/.config/opencode/plugins/juggler-opencode.ts`. Source: `Resources/opencode-plugin/juggler-opencode.txt` (bundled as `.txt` so Xcode 16's filesystem-synchronized group doesn't treat it as TypeScript source and try to compile it; the installer copies it to disk with the `.ts` extension OpenCode expects).

Juggler's onboarding flow and `IntegrationHubView` install the plugin automatically. OpenCode loads plugins from that directory at startup.

## Lifecycle

Unlike Claude Code (stateless hook scripts invoked per event), the OpenCode plugin is a long-lived function. On plugin load it:

1. Captures terminal info from `process.env` (once per OpenCode process).
2. Captures git info via `git rev-parse` (once).
3. Captures tmux pane ID (once).
4. Posts a synthetic `session.created` event immediately.
5. Subscribes to OpenCode events via the returned `event` handler.

The immediate `session.created` post is deliberate: when OpenCode resumes a previous session, the real `session.created` event is not fired, so without this Juggler would not see resumed sessions. See `juggler-opencode.ts:76-78`.

## Tracked Events

Only these events are forwarded (`juggler-opencode.ts:54-61`):

| OpenCode event | Forwarded as |
|----------------|--------------|
| `session.created` | `session.created` |
| `session.status` (with `properties.status.type`) | `session.status.<type>` — e.g., `session.status.idle`, `session.status.busy`, `session.status.retry` |
| `session.compacted` | `session.compacted` |
| `session.deleted` | `session.deleted` |
| `permission.asked` | `permission.asked` |
| `server.instance.disposed` | `server.instance.disposed` |

All other event types are ignored.

`session.status` is a parent event. The plugin reads `event.properties.status.type` and forwards a synthetic `session.status.<type>` event. If `status.type` is missing, the event is dropped. This is the mapping `HookEventMapper.mapOpenCode` expects.

## Payload

Each forwarded event posts to `http://localhost:${JUGGLER_PORT:-7483}/hook` with this body:

```json
{
  "agent": "opencode",
  "event": "session.status.idle",
  "terminal": {
    "cwd": "/path/to/cwd",
    "sessionId": "<ITERM_SESSION_ID or KITTY_WINDOW_ID>",
    "terminalType": "iterm2" | "kitty",
    "kittyListenOn": "unix:/tmp/kitty-12345",
    "kittyPid": "12345"
  },
  "hookInput": { "session_id": "<opencode session id>" },
  "git": { "branch": "main", "repo": "app" },
  "tmux": { "pane": "%0" }
}
```

`hookInput.session_id` is extracted from whichever of these is present: `event.properties.sessionID`, `event.properties.info.id`, `event.session_id`, `event.sessionID` (`juggler-opencode.ts:119-123`).

Kitty fields are only included when `KITTY_WINDOW_ID` is set. `git` and `tmux` blocks are only included when available.

## Failure Handling

Every post uses `fetch` with an `AbortSignal.timeout(2000)` and a `try/catch` that silently swallows errors (`juggler-opencode.ts:99-108`). If Juggler isn't running, the plugin drops events without disturbing OpenCode.

## Differences from Claude Code Hooks

| | Claude Code | OpenCode |
|---|---|---|
| Integration type | Shell hook scripts, one invocation per event | In-process TypeScript plugin |
| Terminal detection | Re-read from env each invocation | Captured once at plugin load |
| Session create on resume | Fired by Claude Code | Synthesized by plugin on load |
| Event namespace | `SessionStart`, `UserPromptSubmit`, `PreToolUse`, ... | `session.created`, `session.status.*`, `permission.asked`, ... |
| Failure behavior | Fire-and-forget `curl --connect-timeout 1` | `fetch` with 2 s timeout, caught errors |

See `docs/tech/hook-server.md` for the event-to-state mapping both agents share.

## Gotchas

- **Resumed sessions need the synthetic `session.created`** — removing the immediate post on plugin load silently breaks session tracking for any resumed OpenCode session.
- **Terminal info is captured once** — if OpenCode is somehow re-parented to a different terminal at runtime, the plugin's cached `terminal` block goes stale. Restart OpenCode to refresh.
- **`session.status` without a `type`** is dropped — if OpenCode changes its event shape, the plugin silently stops posting status updates. Log the payload before dropping if debugging.
- **`JUGGLER_PORT` override** — the plugin respects `$JUGGLER_PORT`. Keep this in sync with `HookServer` if the port is ever customised.

---

[← Back to Tech Overview](overview.md)

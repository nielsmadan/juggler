# Pi Extension

Juggler integrates with [Pi](https://pi.dev) (`@earendil-works/pi-coding-agent`) via a TypeScript **extension** rather than shell hooks — the same in-process model as the OpenCode plugin. The extension runs inside the Pi process, subscribes to Pi's lifecycle events, and posts session events to Juggler's HTTP server.

## Installation

The extension is installed to `${PI_CODING_AGENT_DIR:-~/.pi/agent}/extensions/juggler-pi.ts`. Source: `Resources/pi-extension/juggler-pi.txt` (bundled as `.txt` so Xcode 16's filesystem-synchronized group doesn't treat it as TypeScript source and try to compile it; the installer copies it to disk with the `.ts` extension Pi expects).

`PiExtensionInstaller` (`Services/PiExtensionInstaller.swift`) resolves the directory (honoring `PI_CODING_AGENT_DIR`) and copies the file. Juggler's onboarding flow and `IntegrationHubView` install it automatically. Pi auto-discovers global extensions from that directory — **no trust step and no feature flag** (unlike Codex). The user must restart Pi or run `/reload` for a freshly installed extension to load.

## Lifecycle

Like the OpenCode plugin (and unlike Claude Code's stateless per-event scripts), the extension is a long-lived module. Its default-exported factory runs once when Pi loads it and:

1. Captures terminal info from `process.env` (once per Pi process).
2. Captures git info via `git rev-parse` (once, best effort).
3. Captures tmux pane ID and SSH remote host (once).
4. Subscribes to Pi lifecycle events via `pi.on(...)`.
5. Observes optional permission-system broadcasts via `pi.events.on(...)`.

It never intercepts `tool_call` or any `before_*` event, so it cannot influence Pi's behavior. The permission listeners are observational and use literal channel names, with no import or dependency on the permission package.

## Tracked Events

| Pi event | Posted as | Notes |
|----------|-----------|-------|
| `session_start` | `session_start` | Fires at launch (`reason: "startup"`), before the first prompt — the session appears immediately as `idle`. Also fires on new/resume/reload/fork; re-posting `idle` is correct. |
| `agent_start` | `agent_start` | The agent run begins after a prompt. |
| `agent_settled` | `agent_settled` | Pi's recommended "done" signal — unlike `agent_end`, Pi will not auto-retry/compact/continue after it. |
| `permissions:ui_prompt` | `permission_prompt` | `@gotgenes/pi-permission-system` is about to show a user-facing permission prompt. The session becomes cyclable as `permission`. |
| `permissions:decision` | `permission_resolved` | A user-facing permission gate reached a decision. Silent policy and session decisions are ignored. |
| `session_before_compact` | `session_before_compact` | Compaction starting. |
| `session_compact` | `session_compact_idle` / `session_compact_working` | The extension reads `event.reason`: a manual `/compact` leaves the session idle; a `threshold`/`overflow` compaction is mid-turn and resumes work. |
| `session_shutdown` | `session_shutdown` | Posted **only** for a UI-owning session when `event.reason === "quit"`. Child sessions and new/resume/reload/fork do not remove the terminal session. |

## Payload

Each event posts to `http://localhost:${JUGGLER_PORT:-7483}/hook` with the same unified shape the OpenCode plugin uses:

```json
{
  "agent": "pi",
  "event": "agent_start",
  "terminal": {
    "cwd": "/path/to/cwd",
    "sessionId": "<ITERM_SESSION_ID or KITTY_WINDOW_ID>",
    "terminalType": "iterm2" | "kitty",
    "kittyListenOn": "unix:/tmp/kitty-12345",
    "kittyPid": "12345"
  },
  "hookInput": { "session_id": "<pi session id>" },
  "git": { "branch": "main", "repo": "app" },
  "tmux": { "pane": "%0" },
  "remoteHost": "user@host"
}
```

`hookInput.session_id` is Pi's session id (`ctx.sessionManager.getSessionId()`), included as secondary metadata — Juggler keys sessions by the terminal session id. Kitty fields, `git`, `tmux`, and `remoteHost` are only included when available (`remoteHost` only when `$SSH_CONNECTION` indicates SSH). Permission-system payload details such as commands, paths, and prompt messages are not forwarded; only the synthesized event name is posted.

## Permission-System Integration

Pi core has no native permission concept, so stock Pi sessions never produce a permission state. The optional `@gotgenes/pi-permission-system` package exposes public `permissions:ui_prompt` and `permissions:decision` channels on Pi's shared event bus. Juggler observes those package-specific broadcasts without importing the package; if it is absent, the channels never fire and normal Pi tracking is unchanged.

The extension tracks pending prompt request IDs. A UI prompt records its ID and posts `permission_prompt`; a later user-facing decision consumes one pending prompt and posts `permission_resolved` when none remain. Silent policy decisions, decisions without a pending prompt, and lifecycle events from non-UI child sessions are ignored. Permission payload details and outcomes are not forwarded to Juggler.

Permission resolution maps to `working`, not `idle`, because one tool call can encounter more gates and Pi can continue executing tools or model turns after either approval or denial. `agent_settled` clears pending prompts and remains the definitive idle signal. The decision broadcast is uncorrelated and local to a session event bus, so forwarded subagent prompts can remain `permission` until another parent event or `agent_settled` arrives. The extension unregisters both event-bus listeners during `session_shutdown` because Pi preserves its shared event bus across `/reload`.

## Capability Gaps

- **Other permission extensions:** Juggler supports the public event contract from `@gotgenes/pi-permission-system`; unrelated permission extensions remain `working` unless they emit compatible channels.
- **Session removal on hard kill:** `session_shutdown` fires on graceful exit (Ctrl+C/D, SIGHUP, SIGTERM) but not on SIGKILL or an abruptly closed window — the terminal-bridge cleanup path is the backstop, same as Claude Code's `SessionEnd`.

## Failure Handling

Every post uses `fetch` with `AbortSignal.timeout(2000)` and a `try/catch` that silently swallows errors. Posts share a promise queue so rapid prompt/decision sequences reach Juggler in event order. If Juggler isn't running, the extension drops events without disturbing Pi. `session_shutdown` is awaited so prior state changes and the removal land before Pi exits.

The executable extension contract tests require Node.js 22.6 or newer for native TypeScript type stripping.

## Gotchas

- **Restart / `/reload` required**: a newly installed extension only loads on the next Pi start or `/reload`.
- **`.ts` must ship as `.txt`**: bundling the source as `.ts` makes Xcode 16 route it to Compile Sources instead of the resources bundle; `BundleResourcesTests` pins `juggler-pi.txt`.
- **Terminal info is captured once** at load — if Pi is re-parented to a different terminal at runtime, the cached `terminal` block goes stale. Restart Pi to refresh.
- **`JUGGLER_PORT` override**: the extension respects `$JUGGLER_PORT`. Keep it in sync with `HookServer` if the port is customized.

---

[← Back to Tech Overview](overview.md)

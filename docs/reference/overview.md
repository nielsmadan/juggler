# External Reference

How the things Juggler builds *against* actually behave — the coding agents, the terminal
emulators, and the build toolchain. Everything here is anchored to something outside this repo, so
none of it goes stale when our code changes; it goes stale when the external thing moves.

## The docs

- [**Coding Agent Hook & Plugin APIs**](coding-agent-hooks.md) — how Claude Code, Codex, OpenCode,
  Pi, and Antigravity emit lifecycle events, what each one cannot tell us, and where each diverges
  from its own documentation.
- [**Terminal Control APIs**](terminal-control-apis.md) — what iTerm2, Kitty, WezTerm, and Ghostty
  expose for focusing a pane, recoloring it, and detecting that it is gone.
- [**macOS Build Toolchain**](macos-build-toolchain.md) — `xcodebuild`, Swift Testing,
  SwiftLint/SwiftFormat, Periphery, Sparkle, and the AppKit APIs that do not behave as documented.

## Reading these

Every claim is labelled by how it was established:

- **Verified** — this project ran it and observed the behavior. Where the probe recorded a version,
  that version is quoted. Where it did not, the doc that recorded it is cited with its date.
- **Documented** — upstream says so, with a link. Upstream can change these without telling us.
- **Gotcha** — a footgun or a surprise, from either source.

The **Verified** claims are the ones to re-check first when a dependency moves; no changelog will
mention them.

## Where this sits

| Question | Doc |
|---|---|
| How does the external thing behave? | here |
| How does *our* code handle it? | [`docs/tech/`](../tech/overview.md) |
| What does the feature do for a user? | [`docs/features/`](../features/overview.md) |
| Why did we choose this approach? | the tech doc's rationale section |
| Which terminals/agents *might* we support next? | [`README.md`](../../README.md) |

The per-integration docs under `docs/tech/` are the counterpart to these: `tech/codex-hooks.md`
describes our installer and event mapping, while `reference/coding-agent-hooks.md` describes what
Codex itself does. They cross-link rather than repeat.

Adding a new agent or terminal starts with a capability check against these facts — see the
[`integrate-coding-agent`](../../.claude/skills/integrate-coding-agent/SKILL.md) and
[`integrate-terminal`](../../.claude/skills/integrate-terminal/SKILL.md) skills.

## Version baseline

Versions present on the maintainer's machine when this tree was last revised (2026-08-22). A claim
verified against an older version is stamped with that version in its own doc.

| | Version |
|---|---|
| Claude Code | 2.1.239 |
| Codex | 0.149.0 |
| Pi | 0.84.1 |
| Antigravity (`agy`) | 1.1.11 |
| kitty | 0.45.0 |
| WezTerm | 20240203-110809-5046fc22 |
| OpenCode | not probed |
| iTerm2, Ghostty | not installed |

## Keeping this current

These docs are **not** synced to our source — a refactor here cannot make them wrong. Re-check them
when an external version moves: a new agent release, a terminal upgrade, a toolchain bump. Re-verify
by re-running the probe each claim records. Drop a claim that has stopped being true; this tree holds
current external reality, not its history. If the change forced a change on us, that belongs in a
commit message or a `docs/tech/` doc, not here.

---

[← Back to Overview](../overview.md)

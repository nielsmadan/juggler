# 2026-09-18 HLS version selection

**Result: Pass — older HLS upgraded; equal/newer HLS retained; real hooks worked through the retained newer helper.**

Follow-up to the [v1.9.0 release test](2026-09-18-v1.9.0-release.md), covering shared-binary
selection rather than repeating the full lifecycle suite. The earlier restart-state finding
was not fixed or retested by this pass.

## Artifacts

- Juggler: published `v1.9.0`, commit `4cac16f38799b97e75e3d6b8dac98be14f896e31`
- Release ZIP SHA-256: `86e7fd1a4fe68daf251cf38562d4633d1815f691b1696a1a92c9c7af1f799060`
- Bundled HLS: signed universal `1.0.2`, protocol `1`, extracted from the release ZIP
- Older fixture: real `v1.0.1` source, commit `f40fcfa765760e2a89d249300313e2554d494a82`
- Newer fixture: `1.0.3`, built from pinned source `67bb4ff6404465f6ae915bf0475dec1943bfeb57`
  with only the package version in `Cargo.toml` and `Cargo.lock` changed from `1.0.2` to `1.0.3`
- Fixtures built locally for Apple silicon using Cargo `1.93.1`, `cargo build --release --locked`
- Guest: macOS `15.7.7`, iTerm2 `3.6.11`, Claude Code `2.1.236`; authenticated clone of the prior VM

**1.0.3 is a test fixture, not a published release.** This verifies version selection and use of
a protocol-compatible executable. It does not establish compatibility with future implementation
changes. Fixture source comparison confirmed only the two package-version files changed.

The ZIP digest matched the published asset. Strict nested signature verification passed, and
the extracted helper's checksum matched the helper inside the VM's installed Juggler app.

## Isolated matrix

Each case used its own `XDG_DATA_HOME` and `XDG_STATE_HOME`. No agent configuration was modified
on the host: only `install`, `version`, and `consumers` were invoked.

| Preinstalled HLS | Bundled candidate | Active after install | Result |
|---|---|---|---|
| 1.0.1, protocol 1 | 1.0.2, protocol 1 | 1.0.2; checksum matches bundled helper | Pass |
| 1.0.2, protocol 1 | 1.0.2, protocol 1 | 1.0.2; checksum, inode and mtime unchanged | Pass |
| 1.0.3, protocol 1 | 1.0.2, protocol 1 | 1.0.3; checksum, inode and mtime unchanged | Pass |

Every case retained the full `existing-tool` consumer record unchanged and registered `juggler`
with sink `http://127.0.0.1:7483/hook`. Consumer parsing reported no problems.

Repeat with verified executable paths and a fresh pair of XDG roots for each row:

```sh
"$HLS_PREINSTALLED" install --consumer existing-tool
active="$XDG_DATA_HOME/hooklinesinker/bin/hooklinesinker"
"$active" version --json
"$active" consumers --json
"$HLS_BUNDLED" install --consumer juggler --sink http://127.0.0.1:7483/hook
"$active" version --json
"$active" consumers --json
```

Compare executable checksums, symlink targets, inode and modification time before/after as well
as the reported versions. XDG isolation does not isolate agent configuration paths; do not run
`hooks install` or `uninstall` as part of the host-side matrix.

## VM smoke test

The source VM was shut down before cloning. The disposable clone used a read-only
fixture share. With Juggler stopped, the newer fixture installed consumer `preexisting-tool`.
Then `uninstall --consumer juggler` removed only Juggler's copied registration while the other
consumer retained the helper and all 11 Claude hooks. This established a newer active helper
and no Juggler registration before normal app launch; onboarding/preferences were inherited.

| Check | Result |
|---|---|
| Normal Juggler launch retains active 1.0.3 | Pass; checksum, inode, mtime and symlink unchanged |
| Shared configuration preserved | Pass; existing consumer, all 11 hooks, and Claude settings checksum unchanged |
| Juggler registers itself | Pass; both consumers present and Juggler has the expected local HTTP sink |
| Authenticated Claude session appears | Pass; one idle row in Juggler |
| Real prompt uses retained helper successfully | Pass; `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`; visible working → idle |
| Identity remains stable | Pass; same Claude session, process identity and prefixed iTerm2 ID throughout |
| Helper remains newer after the prompt | Pass; active binary and registrations unchanged |
| Normal `/exit` cleanup | Pass; empty ledger, No Sessions UI, Claude process gone |

The harmless prompt requested foreground `sleep 8`, followed by exactly `vm-newer-hls-ok`.
The expected reply was observed. Hook records reported no current problems. Terminal input used
iTerm2's authenticated Python API; guest accessibility queries checked Juggler's actual rows.

After testing, the disposable clone was shut down and deleted. The original VM was restarted
with Juggler running, its original HLS `1.0.2` checksum intact, only the `juggler` consumer,
and an empty session ledger.

## Evidence and limits

[Sanitized evidence](evidence/2026-09-18/hls-version-selection.json) records source revisions,
fixture hashes, all matrix results, VM binary/configuration snapshots, and observed hook/UI states.
No credentials or conversation transcripts are retained.

This pass does not cover incompatible protocol majors, installation races, corrupted shared
installations, old notify-script migration, or future HLS functionality. Those are separate cases.

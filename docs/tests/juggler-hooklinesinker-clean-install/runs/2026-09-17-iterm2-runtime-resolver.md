# 2026-09-17 iTerm2 runtime resolver follow-up

**Result:** Pass

Procedure: [Clean Juggler and hooklinesinker integration test](../README.md). This follow-up used
a fresh disposable VM to verify the iTerm2 compatibility failure recorded on 2026-09-16 after
the runtime resolver fix. The earlier run already covered real Claude authentication, lifecycle,
hydration, and SessionEnd cleanup, so this run used synthetic local hook events only for the
two-session focus-sync check.

## Tested state

- Git revision: `a6cf11c` plus the local iTerm2 resolver, tests, and documentation changes
- Juggler: `1.8.0`, ad-hoc Debug build
- hooklinesinker: `1.0.2`, protocol `1`
- macOS: `15.7.7` (`24G720`)
- iTerm2: `3.6.11`
- Claude Code: `2.1.236`
- VM: fresh clone of the existing local macOS base, 8 GB RAM

## Results

| Check | Result | Evidence |
|---|---|---|
| Juggler iTerm2 setup check | Pass | All three setup requirements reported ready |
| Managed runtime selection | Pass | Daemon launched with `iterm2env/versions/3.14.0/bin/python3` |
| `iterm2` import | Pass | Selected interpreter imported its managed `iterm2` package |
| Daemon readiness | Pass | Strict socket ping returned `{"status":"ok"}` |
| Terminal information | Pass | Returned the expected session ID, tab, window, and pane metadata |
| Cross-tab activation | Pass | Activating the second prefixed session ID selected its iTerm2 tab |
| Highlighting | Pass | Daemon returned success and the targeted tab visibly changed color |
| Focus synchronization | Pass | After a clean app restart, focusing tab two selected its matching Juggler row |
| Event-listener recovery | Pass | Three app restarts each had a connected listener after the 40-second recovery window |
| hooklinesinker diagnostics | Pass | One Juggler consumer, 11 Claude hooks, no parse problems, dead records, or sink error |

The first post-onboarding listener observation had no Swift subscription socket. A normal Juggler
restart connected it, and the focus-sync check then passed. Five short restart probes observed the
socket within seven seconds twice; all three longer probes observed it within the existing
40-second recovery window. This is consistent with the bridge's asynchronous reconnect schedule,
not a daemon runtime failure.

## Retained evidence

- [`daemon-runtime.txt`](evidence/2026-09-17/daemon-runtime.txt)

Authentication pages, tokens, VNC credentials, screenshots, and temporary tooling were not
retained.

# 2026-09-16 current-checkout run

The test began on 2026-09-16 and completed on 2026-09-17. It exercised the current Juggler
checkout in a new macOS 15 Tart VM with a real authenticated Claude Code session.

Procedure: [Clean Juggler and hooklinesinker integration test](../README.md). The reusable
procedure was written after this run from the executed steps; deviations and missing details are
recorded below.

## Identity and setup

| Item | Value |
|---|---|
| Juggler revision | `a6cf11cc87f1da6f4d7506fb1a3aa928bcaf558f` |
| App source changes | None |
| Other checkout changes | Pre-existing staged loadout and instruction migrations, not part of the app build |
| Build | arm64 Debug, ad-hoc signed |
| VM | New disposable macOS 15 Tart guest, 8 GB RAM |
| iTerm2 | 3.7.2 |
| Claude Code | 2.1.236 |
| hooklinesinker | 1.0.2, protocol 1 |
| Authentication | Real Claude account through native interactive authentication |

The exact original `xcodebuild` invocation was not retained. The build used this temporary
signing override:

```text
CODE_SIGN_IDENTITY = -
CODE_SIGNING_ALLOWED = YES
CODE_SIGNING_REQUIRED = YES
CODE_SIGN_STYLE = Manual
DEVELOPMENT_TEAM =
```

The guest's exact macOS 15 minor version was not recorded. iTerm2's Python runtime was installed
and its Python API was enabled before Juggler onboarding completed.

## Results

| Check | Result | Observation |
|---|---|---|
| First-run onboarding | Pass | Juggler accepted iTerm2 setup and completed onboarding |
| Helper promotion | Pass | The bundled helper promoted to the shared per-user installation |
| Consumer registration | Pass | `juggler` was the sole consumer |
| Claude hooks | Pass | All 11 expected events reported installed |
| hooklinesinker diagnostics | Pass | Protocol 1, no parse problems, dead records, or sink error |
| Session identity | Pass | Claude PID, Claude session ID, and prefixed iTerm2 ID remained stable |
| Idle → working | Pass | `PreToolUse` changed the existing row to `working` during `sleep 20` |
| Working → idle | Pass | `Stop` returned the same row to `idle` |
| Restart hydration | Pass | Relaunching Juggler restored one idle row without duplication |
| SessionEnd cleanup | Pass | `/exit` removed the hooklinesinker record and Juggler row while Juggler stayed running |
| iTerm2 daemon | Fail | The daemon used `/usr/bin/python3`, which could not import `iterm2` |
| Notifications | Limited | macOS denied notification permission to the ad-hoc build |
| Tart guest agent | Limited | Command transport later failed while the VM and VNC remained available |

The restart and SessionEnd command output is in
[lifecycle.txt](evidence/2026-09-16/lifecycle.txt).

## iTerm2 compatibility failure

Juggler's retained logs show an immediate daemon import failure followed by stale-connection
recovery attempts and `daemonNotRunning`. A reduced excerpt is in
[daemon-runtime-failure.txt](evidence/2026-09-16/daemon-runtime-failure.txt).

iTerm2 3.7.2 created versioned roots such as `iterm2env-3.10.19`, `iterm2env-3.14.0`,
`iterm2env-3.7.17`, `iterm2env-3.8.19`, aliases without patch versions, and `iterm2env-79`.
Each contained a `versions/` tree. No unversioned `iterm2env/versions` root appeared. See
[runtime-layout.txt](evidence/2026-09-16/runtime-layout.txt).

At this revision, `ITerm2Bridge.resolveDaemonPython()` searches only the unversioned root. It
therefore fell back to `/usr/bin/python3`, where `import iterm2` failed. Session tracking still
passed because Claude hooks reached Juggler directly; terminal lookup, activation, highlighting,
and focus synchronization were unavailable.

## Conclusion

The run validates the complete hooklinesinker path on a clean machine: promotion, consumer
registration, all Claude hooks, live state transitions, restart hydration, and normal SessionEnd
cleanup. It also identifies an iTerm2 3.7.2 compatibility failure in Python runtime discovery.

The ad-hoc notification denial and failed Tart guest-agent channel are test-environment
limitations. Neither explains the daemon import failure or invalidates the lifecycle results.

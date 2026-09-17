# Clean Juggler and hooklinesinker integration test

Use this procedure to validate a current Juggler checkout against a clean macOS installation,
iTerm2, hooklinesinker, and a real Claude Code session. It covers first-run setup, hook delivery,
restart hydration, SessionEnd cleanup, and iTerm2 daemon compatibility.

Run it before changing onboarding, hooklinesinker integration, hook hydration, or the iTerm2
runtime resolver. Use a disposable Tart VM because the test installs applications, edits the
guest's agent configuration, and requires interactive Claude authentication.

## Prerequisites

- Apple silicon host with Xcode, `just`, Tart, and the repository's build tools
- One local Tart macOS 15 base image; do not download another image
- Normal host memory pressure and enough RAM for one 8 GB guest
- Network access in the guest
- A Claude account supplied through Claude Code's interactive authentication flow

Never capture authentication pages, device codes, browser storage, VNC credentials, or tokens.
Keep the VM name unique and delete only that VM during cleanup.

## Build and stage Juggler

From the repository root:

```bash
run_id="$(date +%Y%m%d-%H%M%S)"
artifact_root="$PWD/build/vm-test-$run_id"
shared="$artifact_root/shared"
mkdir -p "$shared"

just stage-hooklinesinker
xcodebuild \
  -scheme Juggler \
  -configuration Debug \
  -derivedDataPath build \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  DEVELOPMENT_TEAM= \
  build

ditto build/Build/Products/Debug/Juggler.app "$shared/Juggler.app"
```

The ad-hoc signature is only for the disposable VM. Record the tested Git revision and any local
app-source changes in the run record.

## Create and start the VM

List the local images and choose the existing macOS base:

```bash
tart list
sysctl -n kern.memorystatus_vm_pressure_level
```

Continue only when memory pressure is `1`. Then:

```bash
base="<existing-local-base>"
vm="juggler-hls-$run_id"

tart clone "$base" "$vm"
tart set "$vm" --memory 8192
tart run \
  --vnc-experimental \
  --no-graphics \
  --dir=shared:"$shared" \
  "$vm"
```

The final command stays attached. Run later host commands in another terminal. Prefer
`tart exec`; use the private VNC endpoint printed by `tart run` only when real GUI input is
required. In each additional terminal, re-declare the exact VM name printed by the first:

```bash
vm="juggler-hls-<YYYYMMDD-HHMMSS>"
```

## Prepare the guest

Install the current iTerm2 and Claude Code releases from their official Homebrew casks:

```bash
tart exec "$vm" /bin/zsh -lc \
  'brew install --cask iterm2 && brew install --cask claude-code'

tart exec "$vm" /bin/sh -c \
  'ditto "/Volumes/My Shared Files/shared/Juggler.app" /Applications/Juggler.app &&
   xattr -dr com.apple.quarantine /Applications/Juggler.app'
```

In the guest:

1. Launch iTerm2 and complete its first-run prompts.
2. Use **Scripts → Manage → Install Python Runtime**.
3. Enable **iTerm2 → Settings → General → Magic → Enable Python API**.
4. Launch Juggler from `/Applications`.
5. Complete onboarding. Select iTerm2, run its setup check, then install Claude Code hooks.
6. Finish onboarding and open a fresh iTerm2 session.
7. Start `claude`, complete native interactive authentication, and accept the workspace trust
   prompt. Do not export or record authentication material.

Record these versions:

```bash
tart exec "$vm" /bin/sh -c '
  sw_vers
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    /Applications/iTerm.app/Contents/Info.plist
  /opt/homebrew/bin/claude --version 2>/dev/null || claude --version
'
```

## Verify installation

In an iTerm2 shell in the guest:

```bash
hls="$HOME/.local/share/hooklinesinker/bin/hooklinesinker"

"$hls" doctor
"$hls" consumers --json
"$hls" hooks status --agent claude --json
```

Pass criteria:

- `doctor` reports protocol-compatible versions, no parse problems, no dead records, and no
  sink error.
- The promoted binary exists at the path above.
- `juggler` is the only consumer in this clean guest.
- Claude hook status is `installed` with these 11 events:
  `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
  `PostToolUseFailure`, `SubagentStart`, `PermissionRequest`, `PreCompact`, `Stop`,
  `StopFailure`, and `SessionEnd`.

## Verify lifecycle and identity

With Claude idle, capture the terminal ID and the hooklinesinker record:

```bash
printf '%s\n' "$ITERM_SESSION_ID"
pgrep -lf 'Juggler|claude'
"$hls" sessions --json
```

Confirm Juggler shows exactly one idle row and that the record's process PID, Claude session ID,
and prefixed iTerm2 session ID remain stable through the following transitions.

Send Claude this harmless prompt:

```text
Use bash to run sleep 20, then reply with exactly vm-lifecycle-ok.
```

Observe:

1. The row starts `idle`.
2. `PreToolUse` changes it to `working` while `sleep 20` runs.
3. `Stop` changes the same row back to `idle`.
4. No duplicate row appears.

## Verify restart hydration

Leave Claude running and idle. Quit and relaunch Juggler, then run:

```bash
pgrep -lf 'Juggler|claude'
"$hls" sessions --json
"$hls" doctor
```

Juggler must hydrate exactly one idle row. Its Claude session ID, terminal session ID, and Claude
PID must match the pre-restart record. `doctor` must remain clean.

## Verify SessionEnd cleanup

Exit Claude normally with `/exit`, then run:

```bash
pgrep -lf 'Juggler|claude'
"$hls" sessions --json
"$hls" doctor
```

Pass when Claude is gone, Juggler remains running, `sessions` is empty, the Juggler window has no
rows, and `doctor` remains clean.

## Check iTerm2 daemon compatibility

Open **Juggler Settings → Logs**, enable verbose logging, and inspect daemon entries. Record any
startup traceback, recovery loop, or `daemonNotRunning` error.

Also capture the runtime roots without traversing caches:

```bash
find "$HOME/Library/Application Support/iTerm2" \
  -maxdepth 5 \
  \( -name 'iterm2env*' -o -path '*/versions/*' -o -name '.provisioned' \
     -o -path '*/uv/venvs/*/bin/python' \) \
  -print | sort
```

Pass when the daemon reaches `ready`, terminal information resolves, and activation/highlighting
work. Treat a Python import or runtime-discovery failure as a compatibility result. Do not patch
the app during the run.

The ad-hoc build can be denied notification permission. Record that separately; it does not
invalidate hook lifecycle results. A failed Tart guest-agent channel also does not invalidate a
GUI observation when the VM and VNC session remain healthy.

## Cleanup

Export only sanitized evidence needed for the run record. Then:

```bash
tart stop "$vm"
tart delete "$vm"
```

Confirm the name before both commands. Do not run broad cleanup commands.

## Recorded runs

- [2026-09-16 current checkout](runs/2026-09-16-current-checkout.md)
- [2026-09-17 iTerm2 runtime resolver follow-up](runs/2026-09-17-iterm2-runtime-resolver.md)

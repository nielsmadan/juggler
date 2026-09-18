# Juggler and hooklinesinker VM test

Run this before releases or changes to onboarding, helper promotion, hook hydration, or iTerm2
integration. It checks the actual app, terminal, and Claude session together. Run only inside
the designated guest; host Juggler and host agent configuration must remain untouched.

- [Choose the run and prepare artifacts](#choose-the-run-and-prepare-artifacts)
- [Prepare the guest](#prepare-the-guest)
- [Control and observe the guest](#control-and-observe-the-guest)
- [Run the checks in order](#run-the-checks-in-order)
- [Version selection](version-selection.md)
- [Cleanup and evidence](#cleanup-and-evidence)
- [Recorded runs](#recorded-runs)

The shared `macos-vm` skill owns Tart lifecycle, sharing, clipboard, guest permissions, VNC,
and iTerm2 input. Its authoritative source is `loadout/templates/skills/macos-vm/` in the
agentic-coding configuration repository. Load that skill and set `vm_skill` to its directory
before using the commands below. It includes `scripts/iterm.py` and `references/interaction.md`.
Juggler-specific helpers live in this repository's `scripts/tests/`.

## Choose the run and prepare artifacts

Prerequisites: Apple silicon host, Tart with an existing local macOS 15+ base, Python 3,
network access in the guest, and a user available for Claude's interactive authentication.
Debug builds also need Xcode, `just`, and the repo's build dependencies. Published artifacts
need `gh`. The optional version-selection matrix needs Cargo and HLS sources.

| Run | Starting state | Artifact |
|---|---|---|
| Clean install | Clone an untouched local base; authenticate in the guest | Published release or explicit Debug build |
| Release regression | Clone a stopped prepared guest; record inherited preferences/login | Exact published release |
| Version selection | Isolated host matrix, then clone a stopped authenticated guest | Bundled helper plus older/newer fixtures |

Do not call a prepared-guest run a clean installation. Keep one guest running at a time and
check memory pressure as described by `macos-vm`. Record the source guest's initial state so
cleanup can restore it. Check for apps reopening automatically at guest login.

From this repo root, create a fresh staging directory and retain these variables for the run:

```bash
run_id="$(date +%Y%m%d-%H%M%S)"
artifact_root="$PWD/build/vm-test-$run_id"
shared="$artifact_root/shared"
vm="juggler-hls-$run_id"
mkdir -p "$shared"
cp scripts/tests/juggler_vm_ui.applescript scripts/tests/juggler_vm_bridge.py \
  scripts/tests/hls_version_selection.py "$shared/"
```

Choose **one** artifact path.

### Published release

Choose an explicit release tag; never silently replace it with latest during a rerun:

```bash
release="v1.9.0"
gh release download "$release" --repo nielsmadan/juggler --pattern Juggler.zip --dir "$artifact_root"
gh release view "$release" --repo nielsmadan/juggler --json assets \
  --jq '.assets[] | select(.name == "Juggler.zip") | .digest'
shasum -a 256 "$artifact_root/Juggler.zip"
ditto -x -k "$artifact_root/Juggler.zip" "$shared"
codesign --verify --deep --strict --verbose=2 "$shared/Juggler.app"
```

Compare the entire digest and require successful signature verification before proceeding.
Record the release tag, commit and digest. Keep the original signature and quarantine metadata;
never ad-hoc sign or remove quarantine for a release test. CLI ZIP installation verifies the
artifact/integration path; a browser download and first Finder launch is a separate Gatekeeper
UX check. If testing the DMG instead, verify that asset's digest and copy its app from a
read-only mount; record the chosen format. See [release mechanics](../../tech/release.md).

### Current checkout Debug build

```bash
just stage-hooklinesinker
xcodebuild -scheme Juggler -configuration Debug -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES DEVELOPMENT_TEAM= build
ditto build/Build/Products/Debug/Juggler.app "$shared/Juggler.app"
```

Record the Git revision and relevant local source changes. The ad-hoc signature is only for
the disposable guest; notification denial is a separate limitation of this test configuration.
If nested Xcode sandbox initialization fails, use the repo's documented sandbox-disable flags.

## Prepare the guest

Use `macos-vm` to clone the chosen stopped base/prepared guest. Boot visibly with
`--capture-system-keys` and `--dir="shared:$shared:ro"`; keep clipboard sharing enabled for
login-link pasting. Keep the `tart run` process attached and run later commands in another host
shell with the same variables. Wait for a successful bounded `tart exec` readiness probe.

For a fresh guest:

```bash
tart exec "$vm" /bin/zsh -lc 'brew install --cask iterm2 && brew install --cask claude-code'
```

For either run type, quit an existing guest Juggler before replacing the app, then install:

```bash
tart exec "$vm" /bin/sh -c \
  'ditto "/Volumes/My Shared Files/shared/Juggler.app" /Applications/Juggler.app'
```

For **Debug only**, remove quarantine if needed:

```bash
tart exec "$vm" /usr/bin/xattr -dr com.apple.quarantine /Applications/Juggler.app
```

For a **published release**, require these guest checks to succeed instead:

```bash
tart exec "$vm" /usr/bin/codesign --verify --deep --strict --verbose=2 /Applications/Juggler.app
tart exec "$vm" /usr/sbin/spctl --assess --type execute --verbose=2 /Applications/Juggler.app
```

In the guest:

1. Open iTerm2, finish first-run prompts, install its managed Python runtime, and enable its
   Python API as described in `macos-vm`.
2. Open Juggler, complete onboarding with iTerm2 and **Install Claude Code hooks**, then open
   Juggler's session window. In a prepared guest, inspect existing integration state first.
3. Disable automatic update checks/downloads for a fixed-release run; record this deviation.
4. Create a fresh iTerm2 tab and start Claude in the test workspace using the next section.
5. Let the user complete authentication in the **guest browser** and accept workspace trust.
   Do not capture login screens, links or codes. Continue after the user confirms login.

Record guest macOS, Juggler, iTerm2, Claude and HLS versions. Guest commands:

```bash
tart exec "$vm" /bin/sh -c '
  sw_vers
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/Juggler.app/Contents/Info.plist
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/iTerm.app/Contents/Info.plist
  /opt/homebrew/bin/claude --version
  "$HOME/.local/share/hooklinesinker/bin/hooklinesinker" version --json
'
```

## Control and observe the guest

All commands below run on the host and target `$vm`. The shared helper discovers the managed
Python runtime, authenticates to iTerm2 inside the guest, and keeps credentials out of output:

```bash
guest_python="$(python3 "$vm_skill/scripts/iterm.py" --vm "$vm" runtime)"
python3 "$vm_skill/scripts/iterm.py" --vm "$vm" list
session="$(python3 "$vm_skill/scripts/iterm.py" --vm "$vm" new-tab)"
python3 "$vm_skill/scripts/iterm.py" --vm "$vm" send --session "$session" \
  --text 'mkdir -p "$HOME/juggler-vm-qa" && cd "$HOME/juggler-vm-qa" && claude' --submit
```

The helper sends text and Return separately, avoiding Claude's multiline-paste behavior.
This was observed with Claude Code 2.1.236; combining them did not submit the prompt.
Wait for the shell or Claude prompt before sending the next input. After authentication:

```bash
python3 "$vm_skill/scripts/iterm.py" --vm "$vm" screen --session "$session"
tart exec "$vm" /usr/bin/osascript '/Volumes/My Shared Files/shared/juggler_vm_ui.applescript' rows
tart exec "$vm" /bin/sh -c '"$HOME/.local/share/hooklinesinker/bin/hooklinesinker" sessions --json'
```

The AppleScript reads populated and empty Juggler views. It requires the session window open
and guest UI permissions; failures are not empty-state passes. For a changed UI, inspect the
hierarchy using the skill's native-UI instructions and update the selector. Prefer these text
reads to screenshots; use a guest screenshot when visual evidence is necessary.

Do not save raw terminal/UI/ledger output directly into the repo: it includes home paths and
session IDs. Keep it in ignored `build/`, then retain only sanitized evidence.

## Run the checks in order

Poll each expected state with a deadline (up to 30 seconds for hooks/UI, 60 seconds for daemon
recovery). Read all errors and the exit status. Ledger and UI reads are not atomic; repeat after
animations settle before concluding that they disagree.

1. **Installation.** Run guest HLS `doctor`, `consumers --json`, and
   `hooks status --agent claude --json`. A clean install has one `juggler` consumer with sink
   `http://127.0.0.1:7483/hook`, protocol-compatible active helper, and all 11 installed events:
   `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`,
   `SubagentStart`, `PermissionRequest`, `PreCompact`, `Stop`, `StopFailure`, `SessionEnd`.
   Require no parse problems or dead records. A historical sink error after an intentional
   app shutdown needs a fresh delivery check; do not report it as a current failure or silently
   call diagnostics clean.
2. **Idle identity.** Require one idle Claude row and one live ledger record. Record the Claude
   session ID, process identity and prefixed iTerm2 ID locally for comparison. iTerm2's API may
   return a bare UUID; match the ledger's `w…t…p…:UUID` suffix.
3. **Working → idle.** Submit the prompt below. Observe `UserPromptSubmit`/`PreToolUse` and a
   working row while sleep runs, then `PostToolUse`/`Stop`, an idle row and the exact reply.
   Identity must remain stable and there must be no duplicate row.
4. **Permission and recovery.** In Claude's normal manual approval mode, request
   `python3 -c 'print("vm-ui-permission-ok")'`. Verify a real pending approval and Juggler's
   permission row. If an existing allow-rule approves it, the case was not exercised; use a
   fresh test workspace/session with no matching allow-rule. Approve once in the guest and
   require recovery to working/idle. Do not enable bypass permissions.
5. **Restart.** With one idle live record, quit/reopen only guest Juggler using the commands
   below. Require the same row and Claude identity to restore. Repeat with a genuinely pending
   approval: it must restore permission without another Claude message, then approve once.
6. **Two-session navigation.** Start a second Claude in another test tab; require two rows.
   Use the `next`/`previous` UI commands below and verify the actual selected iTerm2 tab changes
   to the corresponding Juggler session. These send the default ⇧⌘J/⇧⌘K bindings; use the
   configured bindings if the prepared guest differs. Direct iTerm2 `select` alone does not
   test Juggler hotkeys. Check focus synchronization by selecting each terminal and observing
   its highlighted Juggler row.
7. **Normal exit.** Submit `/exit` separately to each Claude session. Require no Claude process,
   empty HLS `sessions`, and Juggler's **No Sessions** view while Juggler remains running.

```bash
python3 "$vm_skill/scripts/iterm.py" --vm "$vm" send --session "$session" --submit \
  --text 'Use Bash to run sleep 20 in the foreground, then reply with exactly vm-lifecycle-ok. Do not run it in the background. Do not read or modify any files.'

tart exec "$vm" /usr/bin/osascript -e 'tell application "Juggler" to quit'
tart exec "$vm" /usr/bin/open -a /Applications/Juggler.app

tart exec "$vm" /usr/bin/osascript '/Volumes/My Shared Files/shared/juggler_vm_ui.applescript' next
tart exec "$vm" /usr/bin/osascript '/Volumes/My Shared Files/shared/juggler_vm_ui.applescript' previous
```

Execute each block at its corresponding step, not as one uninterrupted script. Check processes
with guest `pgrep -x Juggler` and `pgrep -x claude`; Claude's exit status `1` means no match.

**Competing-record regression:** the [release run](runs/2026-09-18-v1.9.0-release.md#restart-failure)
documents current permission overwritten by an older idle record after restart. Inspect the
ledger after login and run that case if the precondition exists. Its clean-session creation
sequence remains unknown; mark it **not exercised** when absent. Do not claim deterministic
coverage or inject fabricated records and call that a real login reproduction.

**Daemon compatibility:** inspect Juggler Settings → Logs for readiness, import tracebacks,
recovery loops, and `daemonNotRunning`. Verify terminal information, activation/highlighting,
and focus sync. Use the guest-only bridge helper with the prefixed terminal ID from the ledger:

```bash
terminal_id="<prefixed iTerm2 ID from HLS>"
tart exec "$vm" "$guest_python" '/Volumes/My Shared Files/shared/juggler_vm_bridge.py' ping
tart exec "$vm" "$guest_python" '/Volumes/My Shared Files/shared/juggler_vm_bridge.py' get_session_info --session "$terminal_id"
tart exec "$vm" "$guest_python" '/Volumes/My Shared Files/shared/juggler_vm_bridge.py' activate --session "$terminal_id"
tart exec "$vm" "$guest_python" '/Volumes/My Shared Files/shared/juggler_vm_bridge.py' highlight --session "$terminal_id"
python3 "$vm_skill/scripts/iterm.py" --vm "$vm" list
```

Require `status: ok`, correct terminal metadata, the expected `selectedTab`/`currentWindow`,
and a visibly highlighted tab that resets after two seconds. Explicit `reset` is available
if needed. Keep title/ID output private until sanitized. Capture runtime layout on discovery failure:

```bash
tart exec "$vm" /bin/sh -c 'find "$HOME/Library/Application Support/iTerm2" -maxdepth 5 \
  \( -name "iterm2env*" -o -path "*/versions/*" -o -name .provisioned \) -print'
```

## Cleanup and evidence

For shared-helper upgrade/preservation checks, continue with [version selection](version-selection.md)
after normal Claude exit. Keep fresh-install, prepared-guest and synthetic-fixture results distinct.

Export only sanitized observations and hashes; replace home paths, VM names and session UUIDs
with consistent placeholders. Keep terminal-ID prefixes where relevant. Do not export auth
screens, links, browser storage, VNC passwords, or entire Claude conversations. Store durable
results in `runs/`; keep temporary scripts, sources and raw output under ignored `build/`.

Use `macos-vm` to shut down and delete only the disposable clone. Preserve a prepared guest
only when it is explicitly designated for reuse, and restore any source guest to its prior
state. Report limitations and unexercised cases separately from passes. This procedure does
not cover compaction, crashes, API-error hooks, tmux, other agents/terminals, or notifications.

## Recorded runs

- [2026-09-16 current checkout](runs/2026-09-16-current-checkout.md)
- [2026-09-17 iTerm2 runtime resolver follow-up](runs/2026-09-17-iterm2-runtime-resolver.md)
- [2026-09-18 published v1.9.0 release](runs/2026-09-18-v1.9.0-release.md) — live integration passes; restart with competing records loses the current permission state
- [2026-09-18 HLS version selection](runs/2026-09-18-hls-version-selection.md) — older/equal/newer matrix and newer-helper VM smoke pass

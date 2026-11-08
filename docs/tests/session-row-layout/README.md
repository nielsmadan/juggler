# Session row layout VM test

Run this after changes to the session-monitor row, its slot preferences, or the detail fields
hooklinesinker forwards. It checks the real window with fake agent sessions of every supported
detail-bearing agent, one factor at a time, and records sanitized screenshots. Run only inside a
disposable guest; host Juggler and host agent configuration must remain untouched.

- [Prerequisites](#prerequisites)
- [Build](#build)
- [Guest](#guest)
- [Fixtures](#fixtures)
- [Screenshot matrix](#screenshot-matrix)
- [Sanitize and record](#sanitize-and-record)
- [Runs](#runs)

The shared `macos-vm` skill owns Tart lifecycle, sharing, guest permissions and iTerm2 input
(`loadout/templates/skills/macos-vm/`; set `vm_skill` to its directory). The guest and evidence
conventions follow the [clean-install procedure](../juggler-hooklinesinker-clean-install/README.md).

## Prerequisites

Apple silicon host, Tart, Xcode, `just`, Cargo, Node and Python 3 on the host; the stopped prepared
guest `juggler-release-v1-9-0-20260917-2221` (iTerm2 with its Python API enabled, Juggler onboarding
done, Node available in the guest, no Claude login needed); a checkout of hooklinesinker `dev2`.
Guest screenshots need Screen Recording permission for `screencapture`'s parent process, and the
osascript key and resize helpers need Accessibility and Automation grants for the exec context; grant
them once in the clone and record that. Do not touch host Juggler or any host agent configuration.
The prepared guest runs at 1024 x 768 points, which fits neither eight rows nor the 1200-point wide
case; the guest is switched to 1440 x 1000 below.

## Build

The Debug app embeds hooklinesinker, so the dev2 binary must replace the staged pin before
`xcodebuild`. Do not run `just build`; it re-stages the pinned binary.

```bash
run_id="$(date +%Y%m%d-%H%M%S)"
artifact_root="$PWD/build/vm-test-$run_id"
shared="$artifact_root/shared"
evidence="$artifact_root/evidence"
vm="juggler-rows-$run_id"
hls_src="$HOME/wrksp/hooklinesinker/dev2"
mkdir -p "$shared" "$evidence"

just stage-hooklinesinker
(cd "$hls_src" && cargo build --release)
cp "$hls_src/target/release/hooklinesinker" build/hooklinesinker/hooklinesinker
chmod 755 build/hooklinesinker/hooklinesinker
codesign --force --sign - --identifier com.nielsmadan.hooklinesinker --options runtime \
  build/hooklinesinker/hooklinesinker
codesign --verify --strict build/hooklinesinker/hooklinesinker

xcodebuild -scheme Juggler -configuration Debug -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES DEVELOPMENT_TEAM= build
ditto build/Build/Products/Debug/Juggler.app "$shared/Juggler.app"
"$shared/Juggler.app/Contents/MacOS/hooklinesinker" version --json
```

Record the Juggler and hooklinesinker revisions. The embedded helper reports 1.2.0 and
upgrades the guest's shared 1.0.2 install on first Juggler launch; that install is kept, not deleted.
If nested Xcode sandbox initialization fails, use the repo's documented sandbox-disable flags.

## Guest

Check memory pressure (`sysctl -n kern.memorystatus_vm_pressure_level` is `1`), then clone and boot
visibly with a read-only app share and a writable evidence share:

```bash
env TART_NO_AUTO_PRUNE=1 tart clone juggler-release-v1-9-0-20260917-2221 "$vm"
tart set "$vm" --memory 8192
tart run --capture-system-keys --dir="shared:$shared:ro" --dir="evidence:$evidence" "$vm"
```

Keep `tart run` attached; run the rest in another host shell with the same variables. Wait for a
bounded `tart exec "$vm" /usr/bin/true`. Then install and launch:

```bash
tart exec "$vm" /usr/bin/osascript -e 'tell application "Juggler" to quit' || true
tart exec "$vm" /bin/sh -c \
  'ditto "/Volumes/My Shared Files/shared/Juggler.app" /Applications/Juggler.app'
tart exec "$vm" /usr/bin/xattr -dr com.apple.quarantine /Applications/Juggler.app
tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler SUEnableAutomaticChecks -bool false
tart exec "$vm" /usr/bin/open -a /Applications/Juggler.app
```

Open iTerm2, confirm its Python API works (`python3 "$vm_skill/scripts/iterm.py" --vm "$vm" list`),
open Juggler's session window, and install the Claude, Codex, Qwen, Kimi and Droid hooks from the
Integration Hub only if `hooks status` reports them missing (fixtures ingest directly, so hooks are
optional). Record guest macOS, Juggler, iTerm2 and `hooklinesinker version --json` (expect 1.2.0).

Prepare the desktop. The prepared guest opens an iTerm2 "Software Update" sheet and a "Tips of the
Day" prompt, plus Safari and Reminders windows; dismiss or hide them (System Events `click button
"No"` / `"Remind Me Later"`, `set visible of process "Safari" to false`). The first `screencapture`
in a clone raises a "tart-guest-agent is requesting to bypass the system private window picker"
dialog owned by `UserNotificationCenter`; click its **Allow** button. Enlarge the display, hide the
shortcut footer and the control-bar hint so all eight rows fit, and copy the UI script into the guest
(edits to a read-only share made while the guest runs were not visible to it in the 2026-10-30 run):

```bash
tart exec "$vm" /bin/zsh -lc 'HOMEBREW_NO_AUTO_UPDATE=1 brew install displayplacer'
tart exec "$vm" /bin/zsh -lc 'displayplacer list'   # copy the id, pick the scaled 1440x1000 mode
tart exec "$vm" /bin/zsh -lc 'displayplacer "id:<id> res:1440x1000 hz:60 color_depth:7 scaling:on origin:(0,0) degree:0"'
tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler showShortcutHelper -bool false
tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler controlBarHintDismissed -bool true
tart exec -i "$vm" /bin/sh -c 'mkdir -p "$HOME/row-layout-fixtures" && cat > "$HOME/row-layout-fixtures/juggler_vm_ui.applescript"' \
  < scripts/tests/juggler_vm_ui.applescript
```

`tart set --display` alone does not change the guest's resolution; the guest keeps its own mode.

Before fixtures run, check in the guest that `/Applications/Juggler.app/Contents/MacOS/hooklinesinker
version --json` reports 1.2.0 (the fake agents default to that binary); otherwise pass `--hls-bin`.
Record the guest Node version (the fake agent is CommonJS and needs no particular version).

Slot, title-mode and stats preferences apply live, but each case still starts from a relaunch so it
begins from a known state. Juggler rows are not persisted, yet a relaunched Juggler hydrates every
hooklinesinker-backed row (with its details) from the still-running fake agents, so only the
Antigravity row, which has no hooklinesinker record, needs its fixture restarted (`--only`). Run the
full fixture script once after the first launch (about 35 s per tab) and `--only antigravity` after
each relaunch:

```bash
ui='/Users/admin/row-layout-fixtures/juggler_vm_ui.applescript'
W=480 H=920
place() {
  tart exec -i "$vm" /usr/bin/osascript - <<APPLESCRIPT
tell application "System Events" to tell process "Juggler"
  set frontmost to true
  set position of window "Juggler" to {0, 25}
  set size of window "Juggler" to {$W, $H}
end tell
APPLESCRIPT
}
shot() { tart exec "$vm" /usr/sbin/screencapture -x "/Volumes/My Shared Files/evidence/$1.png"; }
relaunch() {
  tart exec "$vm" /usr/bin/osascript -e 'tell application "Juggler" to quit'; sleep 2
  tart exec "$vm" /usr/bin/open -a /Applications/Juggler.app; sleep 5
  place
  python3 scripts/tests/row_layout_fixtures.py --vm "$vm" --vm-skill "$vm_skill" --only antigravity
  sleep 5
}
slots() {
  local key=(monitorSlotTopLeading monitorSlotTopTrailing monitorSlotBottomLeading monitorSlotBottomTrailing) i
  for i in 1 2 3 4; do
    tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler "${key[$i]}" -string "${@[$i]}"
  done
}
reset_defaults() {
  slots folderPath model gitBranch effort
  W=480 H=920
  tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler sessionTitleMode -string parentAndFolderName
  tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler enableStats -bool true
  tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler monitorShowRenameButton -bool true
  tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler monitorShowNoteButton -bool true
}
```

The four `slots` arguments are top-leading, top-trailing, bottom-leading and bottom-trailing raw values (zsh):
`none folderPath folderName parentAndFolderName tabTitle windowTitle agentTitle gitBranch model effort
permissionMode currentTool lastProblem subagents contextPercent turns runTime`. Title mode raw values are `tabTitle windowTitle
windowAndTabTitle folderName parentAndFolderName agentTitle`.

## Fixtures

`scripts/tests/row_layout_fixtures.py` creates the fake sessions. Preview them on the host with no
VM involved:

```bash
python3 scripts/tests/row_layout_fixtures.py --dry-run
```

Each session is a real iTerm2 tab (`iterm.py new-tab`) so `ITERM_SESSION_ID`, process start time and
tab/window titles are real. In the tab, `scripts/tests/fake_agent.cjs` is copied under the agent's
name (`claude`, `codex`, `qwen`, `kimi`, `droid`) and runs as a Node process, so hooklinesinker's
owning-process lookup finds an agent-named process. It runs `hooklinesinker ingest --agent <a>
--event <e>` for each step with the native payload on stdin, then stays alive. Antigravity has no
hooklinesinker path: its step payloads are POSTed to Juggler's `/hook` in the script's shape. The
script kills the previous fake processes first, so it is idempotent; `--only NAME...` restarts just
the named rows and leaves the others running. Pass `--hls-bin` to override the helper path.

| Row | Agent | Covers |
|---|---|---|
| `claude-long` | claude | 120-character title, deep path, long model id and branch, three turns, two live subagents, working with a tool |
| `claude-permission` | claude | permission state with a pending tool |
| `codex-short` | codex | short values, one subagent, working with `apply_patch` |
| `qwen-problem` | qwen | idle with a last problem and context percent |
| `kimi-working` | kimi | agent session title, working with a tool |
| `droid-sparse` | droid | idle with model, effort and title missing |
| `claude-bare` | claude | idle with every detail missing |
| `antigravity` | antigravity | model forwarded through `/hook`, idle with last problem `error` |

Rows are selected with the arrow keys only (`juggler_vm_ui.applescript down` / `up`); never click a
fake row, because that would try to activate it. Read the visible text with `... rows`.

`up` with no selection selects the last row and `down` with none selects the first, and a relaunch or
iTerm focus resync can leave an arbitrary row selected. Before each shot, read `rows` and press
`down` until the intended first row is the highlighted one (confirm in the screenshot); do not assume `up`.

After each `relaunch`, wait until `rows` shows exactly 8 rows. A full fixture re-run kills the old
fake agents, so their hydrated rows disappear at the next liveness sweep and 8 more iTerm tabs
accumulate; `--only antigravity` adds one tab per relaunch. `rows` reads both the Fair/Prio stack
and the Static/Grouped `List`.

## Screenshot matrix

Start each case from `reset_defaults; relaunch`, change one factor, `relaunch`, wait for rows to
settle, select the first row, and capture. Default window size is the first screenshot;
each filename is the case id below plus `.png`.

| Id | Change from default | Notes |
|---|---|---|
| `00-default` | none | baseline |
| `01-none` | `slots none none none none` | all four None: no grid |
| `02-bottom-none` | `slots folderPath model none none` | bottom grid row not rendered |
| `03-top-none` | `slots none none gitBranch effort` | top grid row not rendered |
| `04-folder-name` | `slots folderName parentAndFolderName gitBranch effort` | slots 1 and 2 |
| `05-tab-window` | `slots tabTitle windowTitle gitBranch effort` | |
| `06-agent-title` | `slots agentTitle model gitBranch effort` | |
| `07-permission` | `slots permissionMode currentTool lastProblem subagents` | |
| `08-context-turns` | `slots contextPercent turns runTime model` | |
| `09-tool-run-time` | `slots currentTool runTime folderPath gitBranch` | |
| `10-title-agent` | `sessionTitleMode agentTitle` | falls back to Parent / Folder Name when no title |
| `11-narrow` | `W=320 place` (use the size the window reports) | narrowest usable; record the actual size |
| `12-wide` | `W=1200 place` | |
| `13-dark` | guest dark appearance, default slots | see below |
| `14-light` | guest light appearance, default slots | |
| `15-stats-off` | `enableStats -bool false` | |
| `16-stats-on` | `enableStats -bool true` | same as `00` for comparison |
| `17-static-list-long` | `queueOrderMode -string static`, long slots | `List` row variant (row padding 0) |
| `18-bottom-trailing-long` | `slots folderPath model gitBranch agentTitle` | long value beside the stats corner |
| `19-settings` | Settings > General (`cmd-,`) | "Row details" 2 x 2 pickers; read the picker's 17 items; rename and note visibility toggles |
| `20-settings-live` | pick Current Tool for Top left in Settings | row updates live; "Replace home path" disabled |
| `21-tilde` | Folder Path back, enable "Replace home path with ~" | paths show `~/...` |
| `22-migration` | quit, delete the four slot keys, `monitorShowFolderPath false`, `monitorShowBranch true`, relaunch | slots migrate to Git Branch / Model / None / Effort, once |
| `23-backburner-details` | backburner the Antigravity row (`l`), POST a `Stop` with a new model | details update on the backburnered row |
| `24-rename-hidden` | `monitorShowRenameButton -bool false` | only the note action is visible in the right-edge stack |
| `25-note-hidden` | `monitorShowNoteButton -bool false` | only the rename action is visible in the right-edge stack |
| `26-actions-hidden` | both visibility keys `false` | no action gap; the state badge owns the right edge |
| `27-note-present` | select the first row, press `M`, enter `Layout note`, then press `Return` | run last; note line appears and the note action uses the filled bubble |

All 17 options appear across cases 00 to 09 (`none` in 01 to 03). `reset_defaults` restores the 480 x 920 window; record the size used per screenshot. Dark mode:

```bash
tart exec "$vm" /usr/bin/osascript -e \
  'tell application "System Events" to tell appearance preferences to set dark mode to true'
```

Use `false` to return. Run cases 11 to 14 once at default slots and once at `slots agentTitle model
gitBranch lastProblem` (long values stress truncation); name those copies with a `-long` suffix.
Run case 27 last because saved notes persist for resumed conversations. Compare it with case 00 and
verify the taller noted row keeps the state badge centered above the stats tabs while the action stack
stays top-aligned.
Example case:

```bash
reset_defaults; slots none none gitBranch effort; relaunch
tart exec "$vm" /usr/bin/osascript "$ui" down   # only if no row is selected; see Fixtures
shot 03-top-none
tart exec "$vm" /usr/bin/osascript "$ui" rows > "$evidence/03-top-none.rows.txt"
```

For each screenshot check: no truncation without an ellipsis, no overlapping text, a blank cell
keeps its row height, a row of two None slots is absent, stats bar presence matches the toggle,
enabled row actions form a compact top-aligned vertical stack after the state badge at the right
edge, the state badge is centered above the stats tabs, text is legible in both appearances, and the
selected row highlights. Record failures with the case id.

## Sanitize and record

Raw screenshots and rows text contain the VM name, home path and session ids; keep them in ignored
`build/`. Fixture content is synthetic, so the usual sanitizing is to crop to the Juggler window
(it sits at `{0, 25}`, so a crop of `W x H` points from there drops the menu bar) and to blank any
iTerm2 window showing the guest's host name between windows, then copy to
`docs/tests/session-row-layout/runs/<date>/`. Write `runs/<date>/README.md` with the identity table
(Juggler and hooklinesinker revisions, guest versions, window sizes), the case results, and
limitations. Report unexercised cases separately from passes.

Shut down and delete only the disposable clone (`tart stop "$vm"; tart delete "$vm"`); the prepared
source guest stays stopped and untouched.

## Runs

| Date | Juggler | hooklinesinker | Cases | Result |
|---|---|---|---|---|
| [2026-10-30](runs/2026-10-30/README.md) | 17176ed Debug | dev2 dd1b71f (1.2.0) | 00 to 23, plus four `-long` variants | 28 pass, 0 fail; popover row not run |

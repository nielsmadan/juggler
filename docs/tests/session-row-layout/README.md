# Session row layout VM test

Run this after changes to the session-monitor row, hidden/backburner dispositions, slot preferences,
or the detail fields hooklinesinker forwards. It checks the real window with fake agent sessions,
one factor at a time, and records sanitized screenshots. Run only inside a disposable Tart clone.
Never launch, quit, activate, replace or reset the user's host Juggler. Never read/write host Juggler
preferences, manipulate host LaunchServices registration, or send fixture requests to host port 7483.
Every app command, preference change, HTTP request and UI action below must target the guest through
`tart exec` or `iterm.py --vm`. Do not launch the prepared source image itself.

- [Prerequisites](#prerequisites)
- [Build](#build)
- [Guest](#guest)
- [Fixtures](#fixtures)
- [Screenshot matrix](#screenshot-matrix)
- [Hidden-session matrix](#hidden-session-matrix)
- [Offline backburner fixtures](#offline-backburner-fixtures)
- [Sanitize and record](#sanitize-and-record)
- [Runs](#runs)

The shared `macos-vm` skill owns Tart lifecycle, sharing, guest permissions and iTerm2 input
(`loadout/templates/skills/macos-vm/`; set `vm_skill` to its directory). The guest and evidence
conventions follow the [clean-install procedure](../juggler-hooklinesinker-clean-install/README.md).

## Prerequisites

Apple silicon host, Tart, Xcode, `just`, Cargo, Node and Python 3 on the host; the stopped prepared
guest `juggler-release-v1-9-0-20260917-2221` (iTerm2 with its Python API enabled, Juggler onboarding
done, Node available in the guest, no Claude login needed).
Guest screenshots need Screen Recording permission for `screencapture`'s parent process, and the
osascript key and resize helpers need Accessibility and Automation grants for the exec context; grant
them once in the clone and record that. Do not touch host Juggler or any host agent configuration.
The prepared guest runs at 1024 x 768 points, which fits neither eight rows nor the 1200-point wide
case; the guest is switched to 1440 x 1000 below.

## Build

Build the current checkout with its pinned hooklinesinker. If testing a different helper, supply
`HOOKLINESINKER_DIST` using the [release instructions](../../tech/release.md) and record its revision.
Do not silently reuse the old run's dev2 helper or assume its 1.2.0 version is current.

```bash
run_id="$(date +%Y%m%d-%H%M%S)"
artifact_root="$PWD/build/vm-test-$run_id"
shared="$artifact_root/shared"
evidence="$artifact_root/evidence"
vm="juggler-rows-$run_id"
mkdir -p "$shared" "$evidence"

timeout 900 just stage-hooklinesinker
build_log="$artifact_root/host-build.log"
build_status=0
timeout 900 xcodebuild -scheme Juggler -configuration Debug -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES DEVELOPMENT_TEAM= REGISTER_APP_WITH_LAUNCH_SERVICES=NO build \
  > "$build_log" 2>&1 || build_status=$?
timeout 30 python3 - "$build_log" "$build_status" <<'PY' || exit 1
from pathlib import Path
import sys

build_log = Path(sys.argv[1])
text = build_log.read_text()
registration = [line for line in text.splitlines()
                if "RegisterWithLaunchServices" in line or "builtin-lsregisterurl" in line]
if registration:
    print("\n".join(registration))
    raise SystemExit("STOP: host app registration ran despite the setting. Build in a disposable Xcode-capable guest.")
status = int(sys.argv[2])
if status:
    raise SystemExit(f"STOP: Xcode exited {status}; inspect the complete log at {build_log}.")
print("Host build passed; no RegisterWithLaunchServices or builtin-lsregisterurl step ran.")
PY
ditto build/Build/Products/Debug/Juggler.app "$shared/Juggler.app"
timeout 30 "$shared/Juggler.app/Contents/MacOS/hooklinesinker" version --json
```

Record the Juggler and hooklinesinker revisions. The bundled helper may upgrade the guest's inherited shared
helper on first launch; a newer compatible shared helper is kept. Record which helper actually becomes active.
If nested Xcode sandbox initialization fails, use the repo's documented sandbox-disable flags.
Keep the complete build log with the run's raw evidence. Every host Xcode compile used for artifact preparation
must pass `REGISTER_APP_WITH_LAUNCH_SERVICES=NO` and the bounded log check above before copying the artifact.
If either registration marker appears, stop this host artifact path and move the build into a disposable
Xcode-capable guest. Do not attempt host LaunchServices cleanup. For other build failures, read the complete
preserved log and its exit status before deciding the next step.

## Guest

Check memory pressure (`sysctl -n kern.memorystatus_vm_pressure_level` is `1`), then clone and boot
visibly with a read-only app share and a writable evidence share:

```bash
# Keep lifecycle and guest commands bounded in every shell used for this run.
tart() {
  if [ "$1" = run ]; then
    command timeout 10800 tart "$@"
  else
    command timeout 90 tart "$@"
  fi
}
timeout 90 env TART_NO_AUTO_PRUNE=1 tart clone juggler-release-v1-9-0-20260917-2221 "$vm"
tart set "$vm" --memory 8192
tart run --capture-system-keys --dir="shared:$shared:ro" --dir="evidence:$evidence" "$vm"
```

Keep `tart run` attached; run the rest in another host shell with the same variables and wrapper.
Use at most three readiness probes (`tart exec "$vm" /usr/bin/true`); stop on persistent failure.
Then install and launch:

```bash
tart exec "$vm" /usr/bin/osascript -e 'tell application "Juggler" to quit' || true
tart exec "$vm" /bin/sh -c \
  'ditto "/Volumes/My Shared Files/shared/Juggler.app" /Applications/Juggler.app'
tart exec "$vm" /usr/bin/xattr -dr com.apple.quarantine /Applications/Juggler.app
tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler SUEnableAutomaticChecks -bool false
tart exec "$vm" /usr/bin/open -a /Applications/Juggler.app
```

Open iTerm2, confirm its Python API works (`timeout 90 python3 "$vm_skill/scripts/iterm.py" --vm "$vm" list`),
open Juggler's session window, and install the Claude, Codex, Qwen, Kimi and Droid hooks from the
Integration Hub only if `hooks status` reports them missing (fixtures ingest directly, so hooks are
optional). Record guest macOS, Juggler, iTerm2 and active `hooklinesinker version --json`.

Prepare the desktop. The prepared guest opens an iTerm2 "Software Update" sheet and a "Tips of the
Day" prompt, plus Safari and Reminders windows; dismiss or hide them (System Events `click button
"No"` / `"Remind Me Later"`, `set visible of process "Safari" to false`). The first `screencapture`
in a clone raises a "tart-guest-agent is requesting to bypass the system private window picker"
dialog owned by `UserNotificationCenter`; click its **Allow** button. Enlarge the display, hide the
shortcut footer and the control-bar hint so all eight rows fit, and copy the UI script into the guest
(edits to a read-only share made while the guest runs were not visible to it in the 2026-10-30 run):

```bash
timeout 900 tart exec "$vm" /bin/zsh -lc 'HOMEBREW_NO_AUTO_UPDATE=1 brew install displayplacer'
tart exec "$vm" /bin/zsh -lc 'displayplacer list'   # copy the id, pick the scaled 1440x1000 mode
tart exec "$vm" /bin/zsh -lc 'displayplacer "id:<id> res:1440x1000 hz:60 color_depth:7 scaling:on origin:(0,0) degree:0"'
tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler showShortcutHelper -bool false
tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler controlBarHintDismissed -bool true
tart exec -i "$vm" /bin/sh -c 'mkdir -p "$HOME/row-layout-fixtures" && cat > "$HOME/row-layout-fixtures/juggler_vm_ui.applescript"' \
  < scripts/tests/juggler_vm_ui.applescript
```

`tart set --display` alone does not change the guest's resolution; the guest keeps its own mode.

Before fixtures run, check the guest's `/Applications/Juggler.app/Contents/MacOS/hooklinesinker
version --json` against the staged artifact (the fake agents default to that binary); pass `--hls-bin`
only for an explicitly chosen alternate helper.
Record the guest Node version (the fake agent is CommonJS and needs no particular version).

Slot, title-mode and stats preferences apply live, but each case still starts from a relaunch so it
begins from a known state. Juggler rows are not persisted, yet a relaunched Juggler hydrates every
hooklinesinker-backed row (with its details) from the still-running fake agents, so only the
Antigravity row, which has no hooklinesinker record, needs its fixture restarted (`--only`). Run the
full fixture script once after the first launch (about 35 s per tab) and `--only antigravity` after
each relaunch:

```bash
timeout 600 python3 scripts/tests/row_layout_fixtures.py --vm "$vm" --vm-skill "$vm_skill"
```

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
  timeout 180 python3 scripts/tests/row_layout_fixtures.py --vm "$vm" --vm-skill "$vm_skill" --only antigravity
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
  tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler monitorRowActionFirst -string rename
  tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler monitorRowActionSecond -string note
  tart exec "$vm" /usr/bin/defaults write com.nielsmadan.Juggler monitorRowActionThird -string hide
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
timeout 30 python3 scripts/tests/row_layout_fixtures.py --dry-run
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

For layout shots select with arrow keys (`juggler_vm_ui.applescript down` / `up`) so focus stays in
the monitor. The hidden-session activation cases below intentionally click/Return on the real guest tabs.
Read the visible text with `... rows`.

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
| `19-settings` | Settings > General (`cmd-,`) | "Row details" 2 x 2 pickers; read the picker's 17 items; three "Action" slot pickers (Rename, Note, Hide, Prio, None) |
| `20-settings-live` | pick Current Tool for Top left in Settings | row updates live; "Replace home path" disabled |
| `21-tilde` | Folder Path back, enable "Replace home path with ~" | paths show `~/...` |
| `22-migration` | quit, delete the four slot keys, `monitorShowFolderPath false`, `monitorShowBranch true`, relaunch | slots migrate to Git Branch / Model / None / Effort, once |
| `23-backburner-details` | backburner the Antigravity row (`l`), POST a `Stop` with a new model | details update on the backburnered row |
| `24-rename-hidden` | `monitorRowActionFirst -string none` | note and hide actions remain |
| `25-note-hidden` | `monitorRowActionSecond -string none` | rename and hide actions remain |
| `26-actions-hidden` | all three `monitorRowAction*` keys `none` | no action gap; the state badge owns the right edge |
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

## Hidden-session matrix

Use a fresh disposable clone for this matrix, or run it after the layout shots and record the
inherited notes/preferences. Allow 90 minutes for H00–H15, 30 minutes for offline cases and 30 minutes
for the action/geometry sweep; stop the run at three hours including setup. Each expected UI/hook
change has a 30-second deadline (60 seconds for terminal recovery); each case has a five-minute cap.
On timeout, record the case as failed or blocked and move to independent cases. Never repeat an
unbounded command. The Tart wrapper above bounds commands and the attached VM lifetime. Prefix
standalone `iterm.py` calls with `timeout 90`; fixture creation has its own `timeout 600` above.

Use Settings to confirm/reset the guest shortcuts before testing: defaults are `⇧⌘K` forward,
`⇧⌘J` backward, `E` Hide/Unhide and `⌘E` Show Hidden. The older UI helper's `next` and `previous`
commands send `⇧⌘J` and `⇧⌘K` respectively; use the actual configured bindings and observed landing,
not those helper names. Turn the shortcut helper on for one monitor/popover shot and enable transient
hints. Restore defaults in the guest at the end. Do not call `reset_defaults` or `relaunch` between
steps that intentionally test same-launch Show Hidden, busy-time continuity or durable intent.

The existing eight fixtures provide idle, permission and busy rows. For deterministic live transitions,
copy the selected Claude row's actual terminal ID from the fixture output/guest ledger into `terminal_id`
and its conversation ID into `agent_session_id` (for example `rl-claude-bare`). Send only to the guest:

```bash
terminal_id='<guest prefixed iTerm2 ID>'
agent_session_id='rl-claude-bare'
event='UserPromptSubmit'  # also Stop, PermissionRequest, PreCompact or PreToolUse
tart exec -i "$vm" /usr/bin/curl --fail-with-body --connect-timeout 2 --max-time 5 \
  -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:7483/hook <<JSON
{"agent":"claude-code","event":"$event","terminal":{"sessionId":"$terminal_id","cwd":"/tmp/hidden-qa","terminalType":"iterm2"},"hookInput":{"session_id":"$agent_session_id"}}
JSON
```

This legacy payload changes the live row but not the hooklinesinker ledger: use it for UI, state,
notification and automation cases only. Relaunch/offline cases must use ingest-backed fixtures below.
Choose another real guest tab for any duplicate-row case; use the same agent/conversation ID there.
Keep raw IDs under ignored `build/`. Drive keys/buttons inside the visible guest or via guest
System Events; bring only the guest monitor/popover to key-window focus. Verify row labels after
each selection change so the intended row receives `E`, `Return`, note and backburner actions.

| Id | Steps | Expected evidence |
|---|---|---|
| H00 default visibility | Start a fresh guest Juggler launch; confirm Show Hidden off, three row actions on; hide one idle row with `E` | Row disappears, X/Y totals remain, Z increases. Top-bar Show Hidden remains available; no terminal activation occurs |
| H01 both shortcuts | Press `⌘E`, select the revealed hidden row, press `E` twice; hold each key briefly | Show Hidden toggles, row unhides then hides; one action per press without repeat. Selection stays usable; hints/settings/legend name both monitor actions |
| H02 both buttons | Toggle the top-bar eye off/on; click the hidden row's right-edge eye to Unhide, then eye-slash to Hide | Top control changes eye-slash/eye and accessibility value Off/On. Row action labels are Hide session/Unhide session; buttons act on their own row without activating its terminal |
| H03 passive presentation | Reveal hidden idle, busy, permission and backburner rows in Fair/Prio, then Static/Grouped | Dimmed rows (55%) carry a passive eye-slash marker alongside the title, retain state/section/order, and have a distinct Unhide action. No overlap or stale animated row |
| H04 selection repair | With Show Hidden off, hide the selected first, middle, last and sole listed row; reveal/select a hidden row and turn Show Hidden off | Prefer next surviving rendered row, then previous; clear selection if none. Arrows and `Return` operate on the highlighted listed row; focus sync never retargets an invisible row |
| H05 all four modes | Repeat hide/reveal/navigation in Fair, Prio, Static and Grouped, with permission-first on/off where supported | List projection and selection agree in section stack and List renderers. Cycling forward/back wraps through only visible-eligible rows regardless of Show Hidden |
| H06 empty states | Hide all tracked rows; open popover with Show Hidden off, then reveal from monitor. Separately stop fixture processes in the guest and use guest Reset Sessions to reach zero rows | Both surfaces show All Sessions Hidden plus monitor guidance, then restored dimmed rows. Genuine zero rows show No Sessions; no invalid selection or crash. Do not count ledger read/UI errors as empty-state evidence |
| H07 popover sharing/context | Turn Show Hidden on in monitor and open popover; press `E`/`⌘E` there; return to monitor and turn it off, reopen popover | Same hidden subset in both views for this launch; monitor-only bindings do not hide/reveal in popover. Shared navigation/rename/note shortcuts still work in the key surface |
| H08 explicit activation/focus | With Show Hidden on, activate a hidden real guest tab once by click and once by selecting it with arrows then `Return`; repeat in popover | Correct iTerm2 tab/pane activates, Hide remains set, popover closes on activation. Reopening either view selects the actual focused revealed row; cycle/current fallback does not displace it |
| H09 cycle and commands | Focus a hidden row; invoke global forward/back, Backburner and Send to Back; repeat with Show Hidden off/on and all idle rows hidden | Cycling moves away only to non-hidden idle/permission rows; global Backburner and Send to Back no-op on hidden focus. All-hidden/no-eligible cycle has no hidden landing. Repeated Send to Back never selects hidden rows |
| H10 automation | Enable Auto Next with non-hidden idle B and hidden idle C; focus A and send A working. Then make all eligible rows busy, leave only C becoming idle for Auto Restart; finally let B become idle | Auto Next lands on B, never C. Hidden transitions neither source nor satisfy automatic activation. Auto Restart may land on B when its visible eligibility is proven; explicit hidden activation still works |
| H11 notifications/old banner | Verify visible working→idle and working→permission notifications for the same conversation; keep both in Notification Center. Hide it, click one old notification and invoke Last Notification. Unhide and click the other old notification. While hidden, repeat both transitions | Hidden transitions create no notifications or Last Notification target, including Show Hidden on. Old notifications never activate their terminal, even after Unhide. macOS may foreground Juggler itself. Record DND, guest permission and signature limitations; an undeliverable baseline makes the case blocked, not passed |
| H12 state/time/stats | Start a busy turn, note Turn/Today values, Hide, wait two 5-second refreshes, reveal; send compacting then idle, repeat permission | Hide preserves underlying state and open turn; compacting continues the same stretch, idle commits it once. Footer always uses `X/Y busy, Z hidden` (including 0 hidden); X/Y include hidden raw rows and duplicate conversation rows. Show Hidden changes none of the counts or daily busy totals |
| H13 durable intent | Hide and backburner different ingest-backed conversations; also hide+backburner one. Quit/reopen only guest Juggler without restarting those fixture processes | Dispositions restore from stable conversation identity, Show Hidden starts off. Revealed rows retain independent hidden/backburner flags. Explicit Reactivate clears shelving without Unhide; unchanged offline snapshots stay shelved |
| H14 conversation scope | Send live rows in two guest tabs with one `(agent, agentSessionID)`; Hide/backburner one, then replace one tab's ID using SessionStart. Resume the original ID in another row | Duplicate rows synchronize disposition; new conversation starts with its own choices. Original conversation retains its saved choices. Repeat same textual ID in another agent namespace to check isolation; count duplicate rows separately in stats |
| H15 Reset Sessions/Remove | Save note `Hidden QA note`, hide+backburner that conversation, use confirmed guest Settings Reset Sessions, then recreate the same ID. Separately Remove a stale ingest-backed row from popover, relaunch, then send new live activity | Successful reset clears rows, stale-binding suppression and hidden/backburner dispositions; note returns, committed busy history remains. Remove is binding suppression, not Hide: live activity can restore the row but does not clear a separately saved Hide. Failed-reset preservation is covered by SessionResetTests; inject a CLI failure only in a separately recorded guest-only fixture, never by changing the host helper |

For H06, stop synthetic processes only inside this clone:

```bash
tart exec "$vm" /usr/bin/pkill -f 'row-layout-fixtures/agents/'
```

Exit 1 means none matched; inspect other failures. Clear rows through guest Settings after processes stop,
then rerun the bounded fixture command for subsequent cases. A reset affects this guest's shared HLS ledger;
no other consumer or real agent should be running there.

Run the action sweep once at default slots and once with all slots None and Stats on (the shortest control
rail), at narrow and default widths. Use all eight `(rename, note, hide)` combinations: `000`, `001`, `010`,
`011`, `100`, `101`, `110`, `111`, where `0` sets that slot to None. Change the three Settings slot pickers live
and record each combination.
For `001` specifically, confirm the eye action alone fits; for `000`, confirm no reserved action gap;
for `111`, hit each action independently with empty/present note and hidden/unhidden rows. Clearing the Hide slot
must not affect rename/note, the top-bar eye, `E`, or `⌘E`.

Compare row heights before/after enabling the third action: the content minimum is still 56 pt, with existing
vertical insets (Fair/Prio 8 pt; Static/Grouped 4 pt) and extra note content only when present. Do not use a
larger row to excuse clipping. The action rail is 16 pt wide plus 4 pt trailing padding; buttons are at most
16 pt tall and shrink with available height/action count, with gaps at most 2 pt. Record actual guest hit
rectangles, test their centers and boundaries for overlap/accidental row activation, and check the small
three-action targets remain usable. This is a visual/usability check, not a claim of a minimum 16 pt height.
Inspect guest accessibility labels: Rename session, Add note/Edit note, Hide session/Unhide session, passive
Hidden session, and Show Hidden with On/Off value. The passive marker must not act as a second button.

Queued activation/delivery races need deterministic suspension and are unit-test coverage, not reliable click
timing tests. In an Xcode-capable disposable guest, the full suite must include
`AutomaticActivationRaceTests`, `HiddenActivationTests`, `SessionNotificationTargetTests`,
`HiddenSectionAnimationTests`, disposition lifecycle/hydration/store tests, presentation/selection, row-action
and stats tests. Follow `just test` with `-parallel-testing-enabled NO` (already in its recipe), wrapped in
`timeout 900` **inside that guest**, never this prepared UI image if it lacks Xcode and never the host.
Record suite results separately from observed UI passes.

## Offline backburner fixtures

Keep the fake process alive across guest Juggler relaunches. Do not rerun its provisioner between shelving
and hydration: a restarted process may get a different binding, which cannot prove a same-binding turn increase.
For a delayed ingest fixture, reuse `fake_agent.cjs` already provisioned in the guest. Write this synthetic spec
under ignored artifacts on the host, copy it into the clone, and start it in a fresh real guest tab:

```bash
cat > "$artifact_root/offline.json" <<'JSON'
{"agent":"claude","transport":"ingest","steps":[
  {"event":"SessionStart","payload":{"session_id":"hidden-offline-1","cwd":"~/work/offline"}},
  {"event":"UserPromptSubmit","payload":{"session_id":"hidden-offline-1","cwd":"~/work/offline"}},
  {"event":"Stop","payload":{"session_id":"hidden-offline-1","cwd":"~/work/offline"},"delayMs":60000},
  {"event":"UserPromptSubmit","payload":{"session_id":"hidden-offline-1","cwd":"~/work/offline"}},
  {"event":"Stop","payload":{"session_id":"hidden-offline-1","cwd":"~/work/offline"}}
]}
JSON
tart exec -i "$vm" /bin/sh -c 'cat > "$HOME/row-layout-fixtures/specs/offline.json"' \
  < "$artifact_root/offline.json"
offline_tab="$(timeout 90 python3 "$vm_skill/scripts/iterm.py" --vm "$vm" new-tab)"
timeout 90 python3 "$vm_skill/scripts/iterm.py" --vm "$vm" send --session "$offline_tab" \
  --text 'mkdir -p "$HOME/work/offline" && node "$HOME/row-layout-fixtures/agents/claude" "$HOME/row-layout-fixtures/specs/offline.json"' --submit
```

Within the initial 60-second pause, verify the first idle state and a valid turn baseline, shelve the row,
optionally Hide it, and quit only guest Juggler. Poll the guest ledger with `tart exec "$vm" /bin/sh -c
'"$HOME/.local/share/hooklinesinker/bin/hooklinesinker" sessions --json'` until the final Stop has a newer
timestamp and a larger explicit count for the same binding (90-second total deadline). Reopen guest Juggler;
the row should wake to idle while retaining Hide. This tests wake by turn increase with a non-prompt snapshot.
Do not infer a pass solely from a larger displayed number: retain the before/after binding and timestamp evidence.

Repeat in separate fresh tabs/conversation IDs, stopping each prior custom fixture by its exact guest spec-path
pattern before starting the next. Change only the post-pause steps:

| Case | Post-pause events | Expected on hydration |
|---|---|---|
| O00 unchanged | Remove all post-pause steps | Still backburner: snapshot predates shelving |
| O01 newer ambiguous | Only PreToolUse (no new prompt) | Still backburner despite newer working snapshot and unchanged count |
| O02 count proof | UserPromptSubmit then Stop (spec above) | Wakes on newer same-binding increased valid count |
| O03 prompt proof | Only UserPromptSubmit | Wakes; this fixture may also increase turns, so it does not isolate the prompt predicate |

O00 needs no wait past the initial Stop; O01–O03 must wait for the post-pause event before relaunch. Each is bounded
to four minutes. A missed shelving window is an invalid setup: stop that custom fixture and retry once with a
longer bounded delay, then mark blocked. For Antigravity, shelf its idle row, relaunch, then send its next live
PreInvocation: it wakes; a row shelved while working must remain shelved. Its normal transport has no startup
snapshot, so do not call that offline-hydration coverage. The strictly newer timestamp, unknown binding,
malformed/missing/negative count and Antigravity snapshot permutations are pinned by the guest unit suite;
mark them not exercised manually unless a recorded guest-only snapshot fixture supplies those exact inputs.

## Sanitize and record

Raw screenshots and rows text contain the VM name, home path and session ids; keep them in ignored
`build/`. Fixture content is synthetic, so the usual sanitizing is to crop to the Juggler window
(it sits at `{0, 25}`, so a crop of `W x H` points from there drops the menu bar) and to blank any
iTerm2 window showing the guest's host name between windows, then copy to
`docs/tests/session-row-layout/runs/<date>/`. Write `runs/<date>/README.md` with the identity table
(Juggler and hooklinesinker revisions, guest versions, window sizes), the case results, and
limitations. Report unexercised cases separately from passes.

Stop custom and standard fake processes by their exact guest-only spec/agent path, quit guest Juggler, then
shut down and delete only the disposable clone (`tart stop "$vm"; tart delete "$vm"`, bounded by the wrapper).
Stop the attached `tart run` process if it remains after guest shutdown. The prepared source guest stays stopped
and untouched. Keep raw evidence in ignored `build/` until sanitized, then remove the run's temporary artifacts
when no longer needed. Never clean host preferences, host LaunchServices or the source image as part of teardown.

## Runs

| Date | Juggler | hooklinesinker | Cases | Result |
|---|---|---|---|---|
| [2026-10-30](runs/2026-10-30/README.md) | 17176ed Debug | dev2 dd1b71f (1.2.0) | 00 to 23, plus four `-long` variants | 28 pass, 0 fail; popover row not run |

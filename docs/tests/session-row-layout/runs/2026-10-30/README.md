# Session row layout run, 2026-10-30

| Item | Value |
|---|---|
| Juggler | `main` 17176ed, Debug 1.11.0, ad-hoc signed |
| hooklinesinker | dev2 `main` dd1b71f, `cargo build --release`, reports 1.2.0 |
| Guest | clone of `juggler-release-v1-9-0-20260917-2221`, macOS 15.7.7 (24G720), iTerm2 3.6.11, Node 24.20.0 |
| Host | Tart 2.41.1 |
| Display | 1440 x 1000 points (scaled, set with `displayplacer`) |
| Window | 480 x 920 points; 11 at 320 x 920, 12 at 1200 x 920 |

Images are cropped to the Juggler window (and Settings window for 19 and 20).

| Case | Result | Observed |
|---|---|---|
| [00-default](00-default.png) | Pass | columns aligned, Folder Path middle-truncated, model and branch tail-truncated, missing effort/model cells blank with row height kept |
| [01-none](01-none.png) | Pass | no grid in any row |
| [02-bottom-none](02-bottom-none.png) | Pass | one grid row |
| [03-top-none](03-top-none.png) | Pass | bottom-only grid takes the badge reserve |
| [04-folder-name](04-folder-name.png) | Pass | `row-layout-long-folder-name`, `packages/row-layo…` |
| [05-tab-window](05-tab-window.png) | Pass | iTerm2 tab titles (`… (node)`), window title `Window 1` (all tabs share one window) |
| [06-agent-title](06-agent-title.png) | Pass | titles for claude-long, claude-permission and kimi; others blank |
| [07-permission](07-permission.png) | Pass | Default, Accept Edits, Yolo, Auto High; Bash, apply_patch, Shell; Rate limited, Error; 1 subagent, 2 subage… |
| [08-context-turns](08-context-turns.png) | Pass | 41% context; 3, 2 and 1 turns; claude-bare blank; run times; Antigravity has no run time (documented) |
| [09-tool-run-time](09-tool-run-time.png) | Pass | top row kept blank where tool and run time are both missing |
| [10-title-agent](10-title-agent.png) | Pass | agent titles, fallback to Parent / Folder Name; the 120-character title wraps to three lines |
| [11-narrow](11-narrow.png), [-long](11-narrow-long.png) | Pass | trailing cells under 40 pt render empty (top row everywhere, bottom row beside Turn + Today) |
| [12-wide](12-wide.png), [-long](12-wide-long.png) | Pass | full values, Folder Path middle-truncated only at the column edge |
| [13-dark](13-dark.png), [-long](13-dark-long.png) | Pass | legible |
| [14-light](14-light.png), [-long](14-light-long.png) | Pass | legible |
| [15-stats-off](15-stats-off.png) | Pass | no corner, no corner reserve |
| [16-stats-on](16-stats-on.png) | Pass | same as 00 |
| [17-static-list-long](17-static-list-long.png) | Pass | `List` variant aligned, no text under badge or corner |
| [18-bottom-trailing-long](18-bottom-trailing-long.png) | Pass | bottom-trailing title stops before the Today and Turn tabs |
| [19-settings](19-settings.png) | Pass | Row details 2 x 2; each picker lists the 17 options in plan order; title modes include Agent Session Title |
| [20-settings-live](20-settings-live.png) | Pass | Current Tool shown without relaunch; "Replace home path with ~" disabled |
| [21-tilde](21-tilde.png) | Pass | `~/work/...` |
| [22-migration](22-migration.png) | Pass | Git Branch / Model / None / Effort; a second launch kept later edits |
| [23-backburner-details](23-backburner-details.png) | Pass | backburnered Antigravity row shows the new model and Output limit |

Checks without a screenshot:

- Antigravity events posted live: `Stop` (`error`) → Error; `PreInvocation` → problem cleared, 1 turn;
  `Stop` (`max_steps_exceeded`) → Step limit; a second `PreInvocation` → 2 turns; `model_stop` → no problem.
- Run Time refreshed without input: 27m → 28m → 30m over 2.5 minutes.
- At 320 points the emptied model cell still carries the full model id as its help text (AX `help`).
- After a relaunch every hooklinesinker row came back hydrated with its details.

Not exercised: the menu-bar popover row (an AX click on the status item did not open the popover);
statuses from a hooklinesinker without `activity` (unit-tested only).

Product observations, not defects against the plan: the session title has no line limit, so a long
Agent Session Title wraps (pre-existing title behaviour); at 320 points the mode bar wraps "Static"
and "Grouped"; the stats chart's white captions are faint on the light background.

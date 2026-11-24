# Session interaction specification

These are agreed requirements for the specification tests, not a description of
everything the current application already implements. Existing tests remain separate.

Here, HUD means the **Session Menu** opened with ⌘⇧M. Auto-reactivate refers to
the **Auto-restart** setting. The **beacon** is the separate status overlay.

## Focus and cycling

In Fair mode, cycling follows the eligible waiting queue and wraps. Clicking a
tracked terminal session makes it the current session. Clicking outside tracked
sessions resets cycling: either direction starts at the first eligible session.
Outside includes the monitor, another app, and an untracked terminal pane.
Selecting a monitor row is not terminal activation.

In Fair and Prio modes, cycling forward from a working or compacting session
starts at the head of the eligible queue. Hidden and backburnered sessions are
excluded. Queue position is meaningful state; the name of the previous command
must not change cycling when the current state and focus are identical.

## Actions and their source

| Action | HUD / global shortcut | Session monitor |
| --- | --- | --- |
| Hide | HUD hides, then activates the first remaining eligible session | Hide without terminal activation |
| Backburner | HUD and global shortcut behave identically; activate the first eligible session only when Go to next session on backburner is enabled | Backburner without terminal activation |
| Priority | Change priority without changing terminal focus | Change priority without terminal activation |
| Unhide | Preserve current state, priority and queue position | Same; never triggers auto-reactivate |
| Unbackburner | Restore Idle using queue placement rules | Same; never triggers auto-reactivate |

Whenever an action intends to activate a session but has no eligible target,
show the All At Work beacon. This includes cycling, HUD Hide, and Backburner
with its next-session setting enabled. Merely changing a monitor row or disabling
Backburner's next-session setting does not create an activation attempt.

## Queue placement

In Fair mode, marking a waiting session priority places it at the end of the
priority group, before ordinary sessions. Removing priority places it directly
after the remaining priority group. Neither action changes focus.

In Fair and Prio modes, Send to Back places the session after all other visible,
eligible waiting sessions, even if marked priority. With Permission First enabled,
it stays within its permission or idle band. The global shortcut then activates
the first remaining eligible session; the monitor action only selects its row.
The flag remains;
normal priority placement resumes on its next Idle
transition. Working and backburnered sessions retain priority for their next Idle
placement. Restoring a backburnered session places it at the bottom in Fair mode,
or the top in Prio mode, honoring priority where that mode supports it.

Unhide reveals the session's current state and queue position; it does not restore
an old state or act as a new Idle transition.

## Automatic activation

Auto-advance applies only when the user starts work in the currently focused
session. Background work elsewhere does not move focus. With auto-advance off,
starting work leaves focus unchanged. Background compaction does not count as
the user starting work.

Auto-reactivate applies when an agent finishes, there were no eligible sessions,
and the user is still inside a tracked terminal session. It is independent of
auto-advance. If another eligible session already existed, there is no automatic
activation. Manual unhide and unbackburner never trigger auto-reactivate.

Hidden and backburnered sessions are never automatic targets. An automatic
activation that has been scheduled must be discarded if the user leaves tracked
sessions before it completes.

## Test boundaries

The new specification suites use two or three sessions per scenario and exercise
real managers/controllers. Terminal I/O and UI presentation are replaced at their
external boundaries. Expectations were written before inspecting
the implementation to connect the fixture. Product discrepancies stay visible as
test failures in the opt-in specification suite. Those specifications are separate
from the Send to Back ordering fix and its regression tests in the normal suite.

The suites are nested under `SessionInteractionSpecifications`, serialized together
because application settings currently use `UserDefaults.standard`. The fixture
restores those settings and removes notification observers after each case.
`just test`, `just coverage`, and their CI/pre-push callers exclude this suite while
requirements are being reconciled. The Send to Back and monitor-isolation regression
tests remain in those normal gates. An unfiltered Xcode test run includes the
specification suite, so select it explicitly when checking the desired behavior.
The dedicated recipe stages the pinned hooklinesinker helper before building:

```sh
timeout 900 just test-interactions
```

This hosted test command launches the test host. Run it from a normal terminal;
building with `build-for-testing` only establishes that the tests compile.

Cycling tests call the real session manager and activator directly; they do not
exercise Carbon key dispatch, the private hotkey presentation selector, or real
mouse events. The empty-cycle beacon assertions cover the activator's cycle policy;
they do not verify that the global handler selected that policy. Focus changes enter through
the manager's terminal-focus interface. Automatic requests are captured from real
notifications and delivered to the real hotkey handler explicitly, allowing tests
to control when focus changes relative to delivery. Work, compaction, tool activity,
completion and session arrival enter through the live hook path with their event
names; direct state updates are only non-automating setup. Additional cases pause bridge
lookup to check invalidation after handling starts. HUD tests open the real menu
manager for the focused session, substituting its panel presentation callback.
OS window focus, actual HUD panel opening/closing, and daemon event timing need
separate UI testing. Other-app and monitor focus are distinct scenarios with the
same model input: the terminal app is inactive.

The focused restoration case exercises the controller's manual-action contract
directly. It is not a monitor UI scenario: real monitor interaction leaves terminal
focus. This case ensures manual restoration suppresses automation independently of
the outside-focus guard.

The HUD currently exposes no Backburner action. Those cases require that action
before proceeding and fail explicitly when it is missing. There is no global
priority shortcut; priority source tests cover HUD and monitor. These are
capability boundaries, not substitutes for the missing interactions.

The Session Menu takes an injected activator and exposes `pendingActivation`, which
the fixture awaits after each menu action, keeping real terminal I/O confined to
the bridge. The menu's Hide action uses that boundary to activate the next session;
its other actions stay synchronous.

---
name: review-swiftui
description: Review SwiftUI presentation and interaction on macOS and other Apple platforms. Checks control semantics, navigation and presentation, adaptive layout, localization, keyboard focus, and window commands against concrete user workflows. Use for "review swiftui", "swiftui review", or reviewing a SwiftUI screen's native behavior. Auto-included by code-review for scoped SwiftUI implementation. Leaves Swift modeling, concurrency, ownership, SwiftUI state, identity, dependencies, and rendering performance to review-swift. Not a general Swift or UIKit/AppKit-only review.
---

# Review SwiftUI

Find consequential UI defects and useful SwiftUI improvements. Start with the app's actual tasks,
not a checklist of missing modifiers. A platform recommendation is a reason to investigate; it is
not proof of a defect or its priority. Review read-only unless the user requests fixes.

## Scope and ownership

Accept the caller's resolved files and diff, an explicit target, or these scope selectors:

| Argument     | Scope                                                                                |
| ------------ | ------------------------------------------------------------------------------------ |
| None         | Files discussed in this conversation; ask for a target if there are none             |
| `--staged`   | `git diff --cached`                                                                  |
| `--changed`  | `git diff` (unstaged tracked changes)                                                |
| `--unpushed` | Local commits in `@{upstream}..HEAD`; review their combined diff from the merge base |
| `--all`      | SwiftUI views/scenes and their UI resources throughout the project                   |

If the upstream or local commit range is absent, report an empty/unresolvable scope. Skip generated
and vendored sources. For diff scopes, report issues introduced or exposed by the change; read
surrounding code and consumers as evidence. Include changed UI resources with their consuming views.

`review-swift` owns types, errors, concurrency, ARC, property-wrapper ownership, observation,
duplicated state, view identity/lifetime/dependencies, and rendering cost. Do not duplicate those
checks. A stale sheet caused by copied state goes there; a wrong presentation host or an unreachable
close control belongs here. Mention an ownership handoff once, without running another review.

Work in this session. `--all` widens coverage, not agent count. Multi-model orchestration belongs to
`code-review --swiftui --all --multi` (substitute the requested scope); route an explicit standalone
`--multi` request there before reviewing rather than inventing a parallel workflow. When called as
its reviewer, do not launch subagents, advisors, or another `code-review`.

## Instructions

1. **Establish context.** Read project instructions and UI/product docs. Record target platforms,
   minimum OS/SDK, native macOS versus Catalyst, supported languages, window model, and the main
   tasks people use this app for. Respect explicit product priorities. Separate supported behavior
   from optional platform polish; do not invent requirements for documents, multiple windows,
   translations, or accessibility features the scope does not discuss.
1. **Trace ordinary flows first.** Follow affected actions from the visible control through its
   command/destination/presentation to the result. Cover selection, navigation, save/submit/cancel,
   and recovery as applicable. Then check alternate input and supported sizes; examine uncommon
   lifecycle sequences only when changed code or a concrete defect points to them.
1. **Apply relevant checks.** Read [references/ui-patterns.md](references/ui-patterns.md), selecting
   the sections the scope touches. Check the project's deployment target before proposing APIs.
   Prefer its working conventions and native semantics; do not mandate rewrites to the newest API.
1. **Try to disprove each claim.** Read parent containers, native control defaults, command menus,
   shortcut handlers, presentation configuration, and alternative routes. A grep miss identifies a
   candidate, not a missing capability. Read the actual framework contract when it decides the
   claim. Prove both the failing branch and the user sequence that can reach it.
1. **Separate evidence from priority.** Use the evidence gate and priority rules below. Consolidate
   repeated instances of the same cause and fix, retaining the locations. Do not count every missing
   modifier as a separate defect.
1. **Report compactly.** State scope and baseline, then verified findings and worthwhile
   suggestions. Keep unresolved runtime questions separate. Stop after covering the requested scope.

## Evidence gate

A finding must identify the affected task, trigger, code path, and consequence. Classify evidence:

- **Code-proven:** source and a verified framework contract establish the result, including the
  relevant enclosing configuration and reachability. Runtime execution is not always necessary.
- **Observed:** a permitted UI test or actual interaction reproduced the result; name the OS, input
  method, and scenario tested.
- **Unverified:** a needed framework behavior, reachable condition, or UI result remains unknown.
  Put this in validation gaps, not in the defect count or a severity section.

Do not claim what VoiceOver announces, how a composite control is exposed, whether Escape dismisses,
or how content clips from modifier names alone. Inspect or test the specific result when source and
framework contracts do not settle it. Follow project rules before launching the app or UI tests. If
unavailable or unauthorized, finish the source review and identify the narrow check still needed.

Absence of `accessibility*`, `keyboardShortcut`, a String Catalog, or a newer navigation API is not
itself a bug. Likewise, presence of a shortcut is not proof that it serves a VoiceOver user's task.
A proposed fix must preserve nested actions, focus behavior, destructive-action safety, deployment
compatibility, and existing alternate routes.

## Priority

Use **Critical Issues (Must Fix)**, **Improvements (Should Fix)**, and **Suggestions (Nice to
Have)**. Assess user consequence, realistic reachability, recovery, and the project's stated
priorities separately from confidence that the code behaves as described. A true finding can be low
priority.

| Tier         | Threshold                                                                                                                                                                                                                                                       |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Must Fix     | A traced path causes data loss, a security failure, a materially wrong operation, or makes a core workflow unusable without reasonable recovery. Name that consequence; "non-native" or "inaccessible" alone is insufficient.                                   |
| Should Fix   | An ordinary supported workflow demonstrably fails or repeatedly imposes substantial friction, or a concrete design defect will create meaningful repair work. State why the remaining routes are inadequate.                                                    |
| Nice to Have | A useful improvement with small practical impact: missing convenience shortcuts, a more idiomatic control, clearer announcements, or a rare recoverable lifecycle defect. Default platform-conformance suggestions here unless stronger impact is demonstrated. |

- A missing Return/Escape shortcut is usually polish when a usable action/dismissal route exists. Do
  not promote it because a sibling happens to use that modifier.
- A no-window fallback that fails after an unusual setup sequence is not automatically a core
  outage. Distinguish that sequence from routine reopen and establish the available recovery.
- Accessibility is neither an automatic severity floor nor an automatic ceiling. Check the actual
  task and available routes for that input method. Do not call a path rare merely because it is used
  by people with disabilities, or assume a mouse route is a usable alternative for them.
- Group optional improvements; do not turn a whole-app review into a list of speculative compliance
  work. A best-practice preference without a concrete benefit is omitted, not scored.

When called by `code-review`, return evidence and impact using its requested format. Its parent owns
independent scoring and final triage in comprehensive mode; quick mode uses its integrated reviewer.
Do not add another scoring round. Standalone, apply the thresholds above yourself.

## Output

Lead with the most consequential verified result. Use only nonempty priority sections. Each entry
contains `file:line`, the affected task and trigger, consequence, evidence, recovery/alternative
considered, and the smallest compatible fix. Be concise; distinguish defects from improvements.
Order by practical impact within a tier, then by effort. Do not label all suggestions "defects".

End with coverage and specific validation gaps. If nothing qualifies, say "No actionable findings."
Do not inflate counts with duplicate instances, speculative runtime failures, or untested advice.

## Examples

- **Named native button shown as an icon:** inspect its effective label and action. An icon-only
  style is not evidence of an unnamed button. No finding solely for missing accessibility modifiers.
- **Setup sheet without explicit keyboard shortcuts:** inspect roles, presentation defaults, and
  existing dismissal paths. If normal completion works, suggest a default action only when useful;
  do not claim Escape is broken without evidence for that OS and presentation.
- **Unobserved open-window notification:** prove the receiver is absent and identify the path that
  reaches the post. A rare, recoverable incomplete-setup case is Nice to Have; a routinely broken
  main entry point may be Should Fix. Do not extrapolate one lifecycle case to every reopen.
- **Wrong document receives a command:** switch focus between two documents and trace the target. A
  demonstrated destructive operation on the wrong document can be Must Fix. Fix command routing;
  leave store ownership analysis to `review-swift`.

## Troubleshooting

- **Too many findings:** recheck each trigger, consequence, and recovery. Merge repeated causes;
  separate suggestions and unverified checks. More checks satisfied is not a better review.
- **A composite row looks inaccessible:** inspect the containing list, actions, selection, and
  accessibility representation. Do not blanket-combine children or assert hidden buttons without
  checking the resulting accessible actions.
- **Only model code is in scope:** report no SwiftUI interaction to review; hand language concerns
  to `review-swift` without launching it.

## Sources

The linked reference records Apple documentation and the limits of each rule. Adapted in part from
Paul Hudson's MIT-licensed
[SwiftUI Agent Skill](https://github.com/twostraws/SwiftUI-Agent-Skill/tree/f2920b63995263f57b3e198674e89a602efba6d2).
Preserve the upstream attribution in [LICENSE](LICENSE). This skill's priority thresholds are review
policy, not severity ratings published by Apple.

# SwiftUI interaction checks

Apply the sections relevant to the scoped code. These are investigation prompts, not requirements
that every app use every API. Check availability against the app's platform, SDK, and minimum OS.
The review's priorities are defined in SKILL.md; Apple does not assign those severity tiers.

## Contents

- [Native controls and accessibility](#native-controls-and-accessibility)
- [Keyboard, focus, and dismissal](#keyboard-focus-and-dismissal)
- [Navigation and presentation](#navigation-and-presentation)
- [macOS windows and commands](#macos-windows-and-commands)
- [Layout and localized content](#layout-and-localized-content)

## Native controls and accessibility

Apple says, “You don’t have to do any extra work to enable these standard accessibility features.”
Its overview covers semantics supplied by native controls including buttons, lists, and sliders.
Start with those defaults, then determine whether the actual content needs refinement.
[SwiftUI accessibility modifiers](https://developer.apple.com/documentation/swiftui/view-accessibility)

- Prefer native controls with styles where the interaction matches their role. Apple advises, “Use
  the styling system over creating a custom view whenever possible.” This preserves semantics; it
  does not make every custom gesture a defect. Inspect labels, values, roles, actions, and the
  parent container before proposing a replacement.
  [Catch up on accessibility in SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10073/)
- A meaningful title can survive an icon-only label style. An explicit accessibility label is not
  mandatory on an already named control. Assess custom icons and decorative images by what they
  communicate, rather than flagging every `Image`.
- For composite rows, inspect grouping and exposed actions. Apple's `.combine` documentation warns,
  “Some properties may be transformed or ignored to achieve the ideal combined result.” It also
  describes default actions becoming named actions and shows a combined view containing a button.
  Losing an independent focus stop does not prove an action is lost. Check the action menu/rotor
  before adding duplicate named actions or blanket-combining an interactive row.
  [AccessibilityChildBehavior.combine](https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior/combine)
- Selection, focus, current-item emphasis, and expansion are different states. `.isSelected` denotes
  that the accessible element is selected. Check whether a native container already supplies the
  state and whether custom state stays accurate when the selection changes.
  [AccessibilityTraits.isSelected](https://developer.apple.com/documentation/swiftui/accessibilitytraits/isselected)
- Inspect information conveyed only through color or movement, reading order, useful value
  announcements, and reachable actions when the affected UI uses them. State the lost information or
  action. Do not infer contrast from a color name or diagnose spoken output from source alone.

Apple's VoiceOver evaluation guidance says controls should be “discoverable, operable, and work
consistently with VoiceOver.” Test the task, including grouped actions, rather than a modifier
count. Record OS, relevant view/state, navigation method, exposed label/state/actions, activation,
and result. This guidance supports evaluating declared VoiceOver support; it does not establish a
defect in a specific untested app or automatically make every refinement release-blocking.
[VoiceOver evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria)

## Keyboard, focus, and dismissal

- Trace the primary action, cancellation, validation, and focus through the presentation. Inspect
  command menus, shortcut scopes, responder handling, button roles, and standard container behavior.
  Check whether a shortcut invokes the intended action or interferes with text editing.
- `.defaultAction` denotes Return; `.cancelAction` denotes Escape. Their absence on a button proves
  only that this declaration does not explicitly assign that shortcut. Missing conveniences are
  suggestions when completion and cancellation remain usable.
  [KeyboardShortcut](https://developer.apple.com/documentation/swiftui/keyboardshortcut)
- Do not infer that a sheet traps the user because no `.cancelAction` appears. Apple's current
  AppKit SwiftUI-sheet bridge documents “Automatic dismissal with the Escape key and disabling
  interactive dismissal” among features shared with SwiftUI sheets. The bridge requires macOS 26+;
  do not use this as proof of historical behavior on every deployment target. Inspect presentation
  kind, dismissal configuration, and focus handling; verify the affected OS when necessary.
  [NSWindow.beginSheet(content:completionHandler:)](<https://developer.apple.com/documentation/appkit/nswindow/beginsheet(content:completionhandler:)>)
- Verify a suggested default action cannot bypass validation, accept a destructive choice, or
  conflict with a multiline text field. A suggested cancellation path must preserve the app's
  unsaved-change policy. Do not add Return/Escape mechanically to every button.

## Navigation and presentation

- Follow value links to a destination registration in the relevant hierarchy. Check parent
  containers and the views installed when the link is used. Check Back, cancellation, and deep links
  only when applicable. Selection-driven detail panes and valid destination-based links are not
  inherently obsolete or wrong.
- Inspect split-view columns at supported sizes. Apple's documented stack collapse concerns specific
  platforms and compact contexts; do not assume every narrow Mac window behaves like iPhone. A
  missing compact-column override is not a defect by itself.
  [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- Check the presentation host, route, and dismissal action against the actual view hierarchy.
  Reading a dismiss action from the wrong environment can target the wrong presentation; prove the
  context before reporting it. Leave duplicated presentation state and view identity issues to
  `review-swift`.

## macOS windows and commands

- Trace visible Open/New/Show commands to a matching scene or an existing window. Distinguish
  `Window`, `WindowGroup`, and ID- versus value-based opening. Do not replace direct AppKit window
  control when it implements the required behavior correctly.
  [OpenWindowAction](https://developer.apple.com/documentation/swiftui/openwindowaction)
- Establish launch, normal close/reopen, and saved-state behavior separately. Launch suppression
  controls presentation when there is no saved state and also affects activation without visible
  windows. It is not a complete restoration policy. Prove which sequence reaches a missing-window
  branch and identify recovery before scoring it; do not infer routine reopen failure from an
  unusual incomplete-setup path.
  [defaultLaunchBehavior(\_:)](<https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior(_:)>)
- For multi-window apps, check a command's target and enablement after switching focus, with no
  selection, and when no document is open. Check the focused-value or responder route, not merely
  whether an API name is present. Report wrong-target behavior separately from ownership design.
  [FocusedValue](https://developer.apple.com/documentation/swiftui/focusedvalue)

## Layout and localized content

- Check supported window sizes, long content, relevant text settings, and translations for clipped
  essential content or inaccessible controls. Fixed dimensions, padding, and custom typography
  require a demonstrated problem before becoming findings. Do not impose iOS touch dimensions or
  Dynamic Type behavior on native desktop controls.
- Use container-proposed space. `ViewThatFits` tries children in preference order against that
  proposal, so it can be a suitable repair when alternative layouts actually solve a fit problem. It
  is not a mandatory wrapper. Apple's example itself uses fixed-width progress views.
  [ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits)
- Check scrollability, safe-area clearance, toolbar overflow, and retained access to actions where
  the scoped layout can constrain them. Background decoration outside a safe area is valid.
- Follow the existing localization pipeline and correct bundle. Many string-label initializers
  accept localization keys; string-literal UI is not proof that localization is impossible. Verify
  the resource lookup, pluralization, and formatted values for supported locales. An English-only
  app can still display regional dates/numbers; lack of translation resources neither requires a
  localization project nor proves that locale-sensitive formatting is irrelevant.
  [Preparing views for localization](https://developer.apple.com/documentation/swiftui/preparing-views-for-localization)
- Loading, empty, and failure views should communicate the condition and the intended next action.
  Review the visible behavior here; state representation and asynchronous ownership stay with
  `review-swift`.

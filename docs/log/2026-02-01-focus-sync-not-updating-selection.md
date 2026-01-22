# Focus Sync Not Updating Selection

**Date:** 2026-02-01
**Status:** Resolved
**Affected Area:** `CyclingEngine.swift`, `SessionManager.swift`, `SessionMonitorView.swift`

## Problem
When clicking on different iTerm2 panes, the main window's selected session doesn't update to match the focused pane.

## Symptoms
- Click between iTerm2 panes, selection in Juggler's main window stays on the same session
- Focus events ARE being received (daemon logs show "Focus changed to: UUID")
- But the UI doesn't respond to focus changes

## Root Cause
Two issues combined:

### 1. UUID Format Mismatch (Regression from CyclingEngine refactor)

Focus events from iTerm2's FocusMonitor send just the UUID:
```
Focus changed to: D3451194-5E1D-46BD-BD0E-331FACDE57CE
```

But session IDs have a prefix:
```
w1t0p0:D3451194-5E1D-46BD-BD0E-331FACDE57CE
```

The old `updateFocusedSession` code handled this:
```swift
// Old code - worked
cyclableSessions.firstIndex(where: { $0.terminalSessionID.hasSuffix(id) })
```

But `CyclingEngine.syncStateToFocus` used exact matching:
```swift
// New code - broken
cyclable.firstIndex(where: { $0.terminalSessionID == focusedID })
```

### 2. SwiftUI Observation Chain Not Triggering

Even after fixing the matching, the `.onChange(of: sessionManager.currentSession?.id)` observer in SessionMonitorView wasn't reliably firing when focus changed. This appears to be because SwiftUI's @Observable doesn't properly track computed property chains through optional chaining.

## Solution

### Fix 1: Restore flexible matching with `hasSuffix`

**CyclingEngine.swift** - `syncStateToFocus`:
```swift
if let idx = cyclable.firstIndex(where: {
    $0.terminalSessionID == focusedID || $0.terminalSessionID.hasSuffix(focusedID)
})
```

**SessionManager.swift** - `currentSession`:
```swift
let session = cyclable.first(where: {
    $0.terminalSessionID == focusedID || $0.terminalSessionID.hasSuffix(focusedID)
})
```

### Fix 2: Add direct observer for focusedSessionID

**SessionMonitorView.swift** - Add reliable observer:
```swift
.onChange(of: sessionManager.focusedSessionID) { _, newFocusedID in
    guard let focusedID = newFocusedID else { return }
    if let index = sessionManager.sessions.firstIndex(where: {
        $0.terminalSessionID == focusedID || $0.terminalSessionID.hasSuffix(focusedID)
    }) {
        selectedIndex = index
    }
}
```

## Investigation Notes
- Initially suspected focus events weren't being received (no "Focus changed" logs)
- Added INFO-level logging to confirm events WERE being received
- Traced through SessionManager.updateFocusedSession → CyclingEngine.syncStateToFocus
- Found the exact matching regression
- After fixing matching, still didn't work - discovered SwiftUI observation issue
- Direct observer on `focusedSessionID` solved the UI update problem

## Prevention
- When refactoring code that handles IDs, check for existing flexible matching patterns (hasSuffix, contains)
- The old code had a comment explaining the UUID format difference - preserve such comments
- Test focus sync manually after any changes to:
  - CyclingEngine
  - SessionManager.updateFocusedSession
  - SessionManager.currentSession
  - SessionMonitorView's onChange observers

## Related
- `iterm2_daemon.py` FocusMonitor sends raw session UUIDs
- Hooks send full `w0t0p0:UUID` format via `$ITERM_SESSION_ID` environment variable
- This same UUID format issue has caused bugs before (see: 2026-01-26 terminal info log)

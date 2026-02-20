# Test Coverage Maximization Design

**Date:** 2026-02-19
**Current coverage:** 20.49% (2,335 / 11,395 executable lines)
**Target:** As high as possible with quality tests (no trivial const-checking)
**Approach:** Extract pure logic from views/managers + deepen tests on existing testable code

## Constraints

- 11,395 executable lines includes ~2,187 from third-party KeyboardShortcuts package (mostly untestable)
- ~6,000 lines are SwiftUI view body closures (not unit-testable without ViewInspector)
- No new test dependencies — pure Swift Testing framework only
- Happy to refactor production code to make it testable

## Strategy

Two-pronged approach:

1. **Deepen coverage** of already-testable code (SessionManager, HookServer, SessionListController, LocalShortcut, etc.)
2. **Extract pure logic** from system-coupled code into standalone testable units

## Section 1: Deepen SessionManager Tests (~170 lines)

SessionManager is 69.86% covered (401/574). Uncovered areas:

- `handleStateTransition`: idle/working time accumulation, queue reordering for fair/prio modes
- `targetIndex`: all 4 QueuePosition cases (topOfIdle, bottomOfIdle, bottomOfBusy, bottomOfBackburner)
- `updateFocusedSession`: activation guard logic (suppress intermediate focus), bare-UUID deduplication
- `addOrUpdateSession`: backburner preservation path, new session focus sync
- `backburnerSession` / `reactivateSession` / `reactivateAllBackburnered`

## Section 2: Test SessionListController (~110 lines)

Currently 43.59% (85/195). Key untested methods:

- `moveSelection`: wrapping behavior, nil start, empty sessions
- `syncSelection`: ID-based preservation across reorders, empty array, out-of-bounds clamping
- `cycleMode`: forward/backward wrapping through all QueueOrderMode cases
- `hasShortcutForKeyCode`: match and no-match cases
- `backburnerSelected` / `reactivateSelected` / `renameSelected`: guard behavior

## Section 3: Test HookServer processRequest (~200 lines)

Currently 25.68% (141/549). Make `processRequest` internal, then test:

- Route dispatch: POST /hook, POST /kitty-event, non-POST = 405, unknown path = 404
- `handleUnifiedHookEvent`: session creation, state updates, terminal type derivation, kitty socket registration
- `handleKittyEvent`: focus_changed → updateFocusedSession, session_terminated → removeSession
- `sendNotificationIfEnabled`: conditional based on UserDefaults keys

## Section 4: Extract Pure Logic (~120 lines)

### SessionStatsCalculator (new file)
Extract from SessionMonitorView:
- `totalIdleTime(sessions:resetDate:isPaused:) -> TimeInterval`
- `totalWorkingTime(sessions:resetDate:isPaused:) -> TimeInterval`
- `idlePercentage(sessions:) -> Double`
- `footerGradientColor(idlePercentage:) -> (red: Double, green: Double, blue: Double)`

### ConfigValidator (new file)
Extract from SettingsView:
- `KittyConfigParser.hasRemoteControl(in: String) -> Bool`
- `KittyConfigParser.hasListenOn(in: String) -> Bool`
- `KittyConfigParser.hasWatcher(in: String) -> Bool`
- `TmuxConfigValidator.isConfigured(contents: String) -> Bool`

### BeaconPositionCalculator (new file)
Extract from BeaconManager:
- `calculateOrigin(position:referenceFrame:panelSize:margin:) -> NSPoint`

### formatDuration (move to top-level)
Move from SessionMonitorView private method to a standalone function.

## Section 5: Make Private Types Internal (~75 lines)

- **ITerm2Bridge**: Change `DaemonRequest`, `DaemonResponse`, `DaemonEvent` from `private` to `internal`. Test encode/decode roundtrips.
- **ITerm2Bridge**: Make `shouldAttemptRecovery` internal. Test all error classification branches.
- **KittyBridge**: Make `rgbToHex` internal. Test edge cases.
- **LocalShortcut**: Cover currently-untested `matches(KeyPress)`, `matches(NSEvent)`, `specialKeyEquivalent`, `eventModifiersToNSModifiers` (currently 58% → target ~90%)

## Section 6: TerminalActivation + Remaining (~80 lines)

- Extract highlight config builders (`tabHighlightConfig`, `paneHighlightConfig`) to take explicit parameters instead of reading UserDefaults
- Make `shouldHighlight` take explicit bools instead of reading UserDefaults
- Cover TerminalBridgeRegistry remaining start/stop paths

## Expected Outcome

~755 new executable lines covered → ~3,090 / 11,395 = **~27%** overall
Excluding third-party: ~3,090 / 9,208 = **~33.5%**

This represents the realistic ceiling for quality unit tests without UI testing frameworks.

## Refactoring Summary

New files:
- `juggler/Models/SessionStatsCalculator.swift`
- `juggler/Models/ConfigValidator.swift`
- `juggler/Models/BeaconPositionCalculator.swift`

Modified files (access control changes):
- `juggler/Services/iTerm2Bridge.swift` — private → internal for types + shouldAttemptRecovery
- `juggler/Services/KittyBridge.swift` — private → internal for rgbToHex
- `juggler/Services/TerminalBridge.swift` — extract config builder params
- `juggler/Views/SessionMonitorView.swift` — move formatDuration out, use SessionStatsCalculator
- `juggler/Views/SettingsView.swift` — use ConfigValidator
- `juggler/Managers/BeaconManager.swift` — use BeaconPositionCalculator

New test files:
- `JugglerTests/SessionStatsCalculatorTests.swift`
- `JugglerTests/ConfigValidatorTests.swift`
- `JugglerTests/BeaconPositionCalculatorTests.swift`
- `JugglerTests/ITerm2BridgeTests.swift`
- `JugglerTests/SessionListControllerTests.swift` (already exists, expand)
- `JugglerTests/TerminalActivationTests.swift`

Expanded test files:
- `JugglerTests/SessionManagerTests.swift`
- `JugglerTests/HookServerTests.swift`
- `JugglerTests/LocalShortcutTests.swift`
- `JugglerTests/KittyBridgeTests.swift`

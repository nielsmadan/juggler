# Test Coverage Maximization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Maximize unit test coverage through refactoring and quality tests — no trivial tests.

**Architecture:** Extract pure logic from views/managers into testable units, deepen tests on already-testable code, and widen access control where needed to test private logic.

**Tech Stack:** Swift Testing framework (`@Test`, `#expect`), `@testable import Juggler`

**Build/test commands:**
- Build: `make build`
- Test: `make test`
- Coverage: `make coverage`

**Test conventions:**
- Swift Testing framework (NOT XCTest) — use `@Test`, `#expect`, `throws`
- `@MainActor` annotation required for tests touching MainActor types
- `makeSession()` helper lives in `JugglerTests/CyclingEngineTests.swift` — available to all test files
- Xcode auto-discovers new test files (PBXFileSystemSynchronizedRootGroup)
- Use `defer` for cleanup of shared state (singletons, UserDefaults)

---

### Task 1: Extract `formatDuration` and `SessionStatsCalculator`

**Files:**
- Create: `juggler/Models/SessionStatsCalculator.swift`
- Modify: `juggler/Views/SessionMonitorView.swift`
- Create: `JugglerTests/SessionStatsCalculatorTests.swift`

**Step 1: Create `SessionStatsCalculator.swift`**

```swift
// juggler/Models/SessionStatsCalculator.swift
import Foundation

/// Pure functions for session statistics — extracted from SessionMonitorView for testability.
enum SessionStatsCalculator {
    static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "<1m" }
        let minutes = Int(seconds) / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h\(String(format: "%02d", remainingMinutes))"
    }

    static func totalIdleTime(sessions: [Session], resetDate: Date?, isPaused: Bool) -> TimeInterval {
        guard !isPaused else { return 0 }
        return sessions.reduce(0) { total, session in
            guard let resetDate else {
                return total + session.totalIdleTime
            }
            if session.startedAt >= resetDate {
                return total + session.totalIdleTime
            }
            if let lastBecameIdle = session.lastBecameIdle, lastBecameIdle >= resetDate {
                return total + (session.currentIdleDuration ?? 0)
            }
            return total
        }
    }

    static func totalWorkingTime(sessions: [Session], resetDate: Date?, isPaused: Bool) -> TimeInterval {
        guard !isPaused else { return 0 }
        return sessions.reduce(0) { total, session in
            guard let resetDate else {
                return total + session.totalWorkingTime
            }
            if session.startedAt >= resetDate {
                return total + session.totalWorkingTime
            }
            if let lastBecameWorking = session.lastBecameWorking, lastBecameWorking >= resetDate {
                return total + (session.currentWorkingDuration ?? 0)
            }
            return total
        }
    }

    static func idlePercentage(sessions: [Session]) -> Double {
        guard !sessions.isEmpty else { return 1.0 }
        let idleCount = sessions.filter { $0.state == .idle || $0.state == .permission }.count
        return Double(idleCount) / Double(sessions.count)
    }

    static func footerGradientComponents(idlePercentage: Double) -> (red: Double, green: Double, blue: Double) {
        (
            red: 0.3 + (0.3 * idlePercentage),
            green: 0.5 - (0.2 * idlePercentage),
            blue: 0.3
        )
    }
}
```

**Step 2: Update `SessionMonitorView.swift` to use extracted functions**

Replace the private `formatDuration`, `totalIdleTimeForFooter`, `totalWorkingTimeForFooter`, `idlePercentage`, and `footerGradientColor` with calls to `SessionStatsCalculator`. For example:

```swift
// Replace private func formatDuration with:
// SessionStatsCalculator.formatDuration(seconds)

// Replace private var totalIdleTimeForFooter with:
// SessionStatsCalculator.totalIdleTime(sessions: sessionManager.sessions, resetDate: globalStatsResetDate, isPaused: isPaused)

// Replace private var idlePercentage with:
// SessionStatsCalculator.idlePercentage(sessions: sessionManager.sessions)

// Replace private var footerGradientColor with:
// let components = SessionStatsCalculator.footerGradientComponents(idlePercentage: idlePercentage)
// Color(red: components.red, green: components.green, blue: components.blue)
```

**Step 3: Create `SessionStatsCalculatorTests.swift`**

```swift
import Foundation
@testable import Juggler
import Testing

// MARK: - formatDuration Tests

@Test func formatDuration_underOneMinute_returnsLessThan1m() {
    #expect(SessionStatsCalculator.formatDuration(0) == "<1m")
    #expect(SessionStatsCalculator.formatDuration(30) == "<1m")
    #expect(SessionStatsCalculator.formatDuration(59) == "<1m")
}

@Test func formatDuration_minutes_returnsMinutes() {
    #expect(SessionStatsCalculator.formatDuration(60) == "1m")
    #expect(SessionStatsCalculator.formatDuration(120) == "2m")
    #expect(SessionStatsCalculator.formatDuration(3540) == "59m")
}

@Test func formatDuration_hours_returnsHoursAndMinutes() {
    #expect(SessionStatsCalculator.formatDuration(3600) == "1h00")
    #expect(SessionStatsCalculator.formatDuration(3660) == "1h01")
    #expect(SessionStatsCalculator.formatDuration(7500) == "2h05")
}

// MARK: - idlePercentage Tests

@Test func idlePercentage_empty_returnsOne() {
    #expect(SessionStatsCalculator.idlePercentage(sessions: []) == 1.0)
}

@Test func idlePercentage_allIdle_returnsOne() {
    let sessions = [makeSession("s1", state: .idle), makeSession("s2", state: .permission)]
    #expect(SessionStatsCalculator.idlePercentage(sessions: sessions) == 1.0)
}

@Test func idlePercentage_halfIdle_returnsHalf() {
    let sessions = [makeSession("s1", state: .idle), makeSession("s2", state: .working)]
    #expect(SessionStatsCalculator.idlePercentage(sessions: sessions) == 0.5)
}

@Test func idlePercentage_noneIdle_returnsZero() {
    let sessions = [makeSession("s1", state: .working), makeSession("s2", state: .backburner)]
    #expect(SessionStatsCalculator.idlePercentage(sessions: sessions) == 0.0)
}

// MARK: - footerGradientComponents Tests

@Test func footerGradient_zeroIdle_greener() {
    let c = SessionStatsCalculator.footerGradientComponents(idlePercentage: 0.0)
    #expect(c.red == 0.3)
    #expect(c.green == 0.5)
    #expect(c.blue == 0.3)
}

@Test func footerGradient_fullIdle_redder() {
    let c = SessionStatsCalculator.footerGradientComponents(idlePercentage: 1.0)
    #expect(c.red == 0.6)
    #expect(c.green == 0.3)
    #expect(c.blue == 0.3)
}

// MARK: - totalIdleTime Tests

@Test func totalIdleTime_paused_returnsZero() {
    let sessions = [makeSession("s1", state: .idle)]
    let result = SessionStatsCalculator.totalIdleTime(sessions: sessions, resetDate: nil, isPaused: true)
    #expect(result == 0)
}

@Test func totalIdleTime_noResetDate_sumsAll() {
    var s1 = makeSession("s1", state: .working)
    s1.accumulatedIdleTime = 100
    var s2 = makeSession("s2", state: .working)
    s2.accumulatedIdleTime = 200
    let result = SessionStatsCalculator.totalIdleTime(sessions: [s1, s2], resetDate: nil, isPaused: false)
    #expect(result == 300)
}

@Test func totalIdleTime_withResetDate_filtersOldSessions() {
    let resetDate = Date(timeIntervalSince1970: 1000)
    var s1 = makeSession("s1", state: .working)
    s1.startedAt = Date(timeIntervalSince1970: 500) // before reset
    s1.accumulatedIdleTime = 100
    var s2 = makeSession("s2", state: .working)
    s2.startedAt = Date(timeIntervalSince1970: 1500) // after reset
    s2.accumulatedIdleTime = 200
    let result = SessionStatsCalculator.totalIdleTime(sessions: [s1, s2], resetDate: resetDate, isPaused: false)
    #expect(result == 200) // only s2 counted
}

// MARK: - totalWorkingTime Tests

@Test func totalWorkingTime_paused_returnsZero() {
    var s = makeSession("s1", state: .idle)
    s.accumulatedWorkingTime = 500
    let result = SessionStatsCalculator.totalWorkingTime(sessions: [s], resetDate: nil, isPaused: true)
    #expect(result == 0)
}

@Test func totalWorkingTime_noResetDate_sumsAll() {
    var s1 = makeSession("s1", state: .idle)
    s1.accumulatedWorkingTime = 100
    var s2 = makeSession("s2", state: .idle)
    s2.accumulatedWorkingTime = 200
    let result = SessionStatsCalculator.totalWorkingTime(sessions: [s1, s2], resetDate: nil, isPaused: false)
    #expect(result == 300)
}
```

**Step 4: Run tests**

Run: `make test`
Expected: All pass, including new SessionStatsCalculator tests.

**Step 5: Commit**

```
feat: extract SessionStatsCalculator from SessionMonitorView for testability
```

---

### Task 2: Extract `ConfigValidator`

**Files:**
- Create: `juggler/Models/ConfigValidator.swift`
- Modify: `juggler/Views/SettingsView.swift`
- Create: `JugglerTests/ConfigValidatorTests.swift`

**Step 1: Create `ConfigValidator.swift`**

```swift
// juggler/Models/ConfigValidator.swift
import Foundation

/// Kitty config file parsing — extracted from SettingsView for testability.
enum KittyConfigParser {
    static func hasRemoteControl(in contents: String) -> Bool {
        contents.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("#") && trimmed.hasPrefix("allow_remote_control")
                && (trimmed.contains("yes") || trimmed.contains("socket"))
        }
    }

    static func hasListenOn(in contents: String) -> Bool {
        contents.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("listen_on") && !trimmed.hasPrefix("#")
        }
    }

    static func hasWatcher(in contents: String) -> Bool {
        contents.contains("juggler_watcher.py")
    }
}

/// tmux config validation — extracted from SettingsView for testability.
enum TmuxConfigValidator {
    static func isConfigured(contents: String) -> Bool {
        contents.contains("update-environment")
            && (contents.contains("ITERM_SESSION_ID") || contents.contains("KITTY_WINDOW_ID"))
    }
}
```

**Step 2: Update `SettingsView.swift` `checkKittyStatus()` and `checkTmuxConfigured()`**

Replace the inline parsing logic with calls to `KittyConfigParser` and `TmuxConfigValidator`. For example in `checkKittyStatus()`:

```swift
if let contents = try? String(contentsOfFile: kittyConfPath, encoding: .utf8) {
    kittyRemoteControl = KittyConfigParser.hasRemoteControl(in: contents)
    kittyListenOn = KittyConfigParser.hasListenOn(in: contents)
    kittyWatcherInstalled = KittyConfigParser.hasWatcher(in: contents)
} else { ... }
```

And in `checkTmuxConfigured()`:

```swift
let contents = try String(contentsOfFile: tmuxConfPath, encoding: .utf8)
tmuxConfigured = TmuxConfigValidator.isConfigured(contents: contents)
```

**Step 3: Create `ConfigValidatorTests.swift`**

```swift
import Foundation
@testable import Juggler
import Testing

// MARK: - KittyConfigParser Tests

@Test func kittyConfig_remoteControl_socketOnly() {
    #expect(KittyConfigParser.hasRemoteControl(in: "allow_remote_control socket-only") == true)
}

@Test func kittyConfig_remoteControl_yes() {
    #expect(KittyConfigParser.hasRemoteControl(in: "allow_remote_control yes") == true)
}

@Test func kittyConfig_remoteControl_commented() {
    #expect(KittyConfigParser.hasRemoteControl(in: "# allow_remote_control yes") == false)
}

@Test func kittyConfig_remoteControl_no() {
    #expect(KittyConfigParser.hasRemoteControl(in: "allow_remote_control no") == false)
}

@Test func kittyConfig_remoteControl_absent() {
    #expect(KittyConfigParser.hasRemoteControl(in: "font_size 12\nsome_other_setting yes") == false)
}

@Test func kittyConfig_remoteControl_multiline() {
    let config = """
    font_size 12
    # allow_remote_control yes
    allow_remote_control socket-only
    background #000000
    """
    #expect(KittyConfigParser.hasRemoteControl(in: config) == true)
}

@Test func kittyConfig_listenOn_present() {
    #expect(KittyConfigParser.hasListenOn(in: "listen_on unix:/tmp/kitty-{kitty_pid}") == true)
}

@Test func kittyConfig_listenOn_commented() {
    #expect(KittyConfigParser.hasListenOn(in: "# listen_on unix:/tmp/kitty") == false)
}

@Test func kittyConfig_listenOn_absent() {
    #expect(KittyConfigParser.hasListenOn(in: "font_size 12") == false)
}

@Test func kittyConfig_watcher_present() {
    #expect(KittyConfigParser.hasWatcher(in: "watcher juggler_watcher.py") == true)
}

@Test func kittyConfig_watcher_absent() {
    #expect(KittyConfigParser.hasWatcher(in: "font_size 12") == false)
}

// MARK: - TmuxConfigValidator Tests

@Test func tmuxConfig_configured_withItermVar() {
    let config = "set-option -ga update-environment ' ITERM_SESSION_ID'"
    #expect(TmuxConfigValidator.isConfigured(contents: config) == true)
}

@Test func tmuxConfig_configured_withKittyVar() {
    let config = "set-option -ga update-environment ' KITTY_WINDOW_ID'"
    #expect(TmuxConfigValidator.isConfigured(contents: config) == true)
}

@Test func tmuxConfig_notConfigured_noUpdateEnvironment() {
    #expect(TmuxConfigValidator.isConfigured(contents: "set-option -g default-terminal screen") == false)
}

@Test func tmuxConfig_notConfigured_noTerminalVars() {
    #expect(TmuxConfigValidator.isConfigured(contents: "set-option -ga update-environment ' FOO'") == false)
}

@Test func tmuxConfig_empty() {
    #expect(TmuxConfigValidator.isConfigured(contents: "") == false)
}
```

**Step 4: Run tests**

Run: `make test`
Expected: All pass.

**Step 5: Commit**

```
feat: extract ConfigValidator from SettingsView for testability
```

---

### Task 3: Extract `BeaconPositionCalculator`

**Files:**
- Create: `juggler/Models/BeaconPositionCalculator.swift`
- Modify: `juggler/Managers/BeaconManager.swift`
- Create: `JugglerTests/BeaconPositionCalculatorTests.swift`

**Step 1: Create `BeaconPositionCalculator.swift`**

```swift
// juggler/Models/BeaconPositionCalculator.swift
import Foundation

/// Pure geometry for beacon panel positioning — extracted from BeaconManager for testability.
enum BeaconPositionCalculator {
    static func calculateOrigin(
        position: BeaconPosition,
        referenceFrame: NSRect,
        panelSize: NSSize,
        margin: CGFloat = 40
    ) -> NSPoint {
        switch position {
        case .center:
            NSPoint(
                x: referenceFrame.midX - panelSize.width / 2,
                y: referenceFrame.midY - panelSize.height / 2
            )
        case .topLeft:
            NSPoint(
                x: referenceFrame.minX + margin,
                y: referenceFrame.maxY - panelSize.height - margin
            )
        case .topRight:
            NSPoint(
                x: referenceFrame.maxX - panelSize.width - margin,
                y: referenceFrame.maxY - panelSize.height - margin
            )
        case .bottomLeft:
            NSPoint(
                x: referenceFrame.minX + margin,
                y: referenceFrame.minY + margin
            )
        case .bottomRight:
            NSPoint(
                x: referenceFrame.maxX - panelSize.width - margin,
                y: referenceFrame.minY + margin
            )
        }
    }
}
```

**Step 2: Update `BeaconManager.positionPanel` to use calculator**

Replace the switch statement in `positionPanel(panelSize:)` with:

```swift
let origin = BeaconPositionCalculator.calculateOrigin(
    position: position,
    referenceFrame: referenceFrame,
    panelSize: panelSize
)
panel?.setFrameOrigin(origin)
```

**Step 3: Create `BeaconPositionCalculatorTests.swift`**

```swift
import Foundation
@testable import Juggler
import Testing

@Test func beaconPosition_center() {
    let frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let panel = NSSize(width: 200, height: 60)
    let origin = BeaconPositionCalculator.calculateOrigin(position: .center, referenceFrame: frame, panelSize: panel)
    #expect(origin.x == 400) // (1000/2) - (200/2)
    #expect(origin.y == 370) // (800/2) - (60/2)
}

@Test func beaconPosition_topLeft() {
    let frame = NSRect(x: 100, y: 100, width: 1000, height: 800)
    let panel = NSSize(width: 200, height: 60)
    let origin = BeaconPositionCalculator.calculateOrigin(position: .topLeft, referenceFrame: frame, panelSize: panel)
    #expect(origin.x == 140) // 100 + 40
    #expect(origin.y == 800) // 100 + 800 - 60 - 40
}

@Test func beaconPosition_topRight() {
    let frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let panel = NSSize(width: 200, height: 60)
    let origin = BeaconPositionCalculator.calculateOrigin(position: .topRight, referenceFrame: frame, panelSize: panel)
    #expect(origin.x == 760) // 1000 - 200 - 40
    #expect(origin.y == 700) // 800 - 60 - 40
}

@Test func beaconPosition_bottomLeft() {
    let frame = NSRect(x: 50, y: 50, width: 1000, height: 800)
    let panel = NSSize(width: 200, height: 60)
    let origin = BeaconPositionCalculator.calculateOrigin(position: .bottomLeft, referenceFrame: frame, panelSize: panel)
    #expect(origin.x == 90) // 50 + 40
    #expect(origin.y == 90) // 50 + 40
}

@Test func beaconPosition_bottomRight() {
    let frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let panel = NSSize(width: 200, height: 60)
    let origin = BeaconPositionCalculator.calculateOrigin(position: .bottomRight, referenceFrame: frame, panelSize: panel)
    #expect(origin.x == 760) // 1000 - 200 - 40
    #expect(origin.y == 40)  // 0 + 40
}

@Test func beaconPosition_customMargin() {
    let frame = NSRect(x: 0, y: 0, width: 500, height: 500)
    let panel = NSSize(width: 100, height: 50)
    let origin = BeaconPositionCalculator.calculateOrigin(position: .topLeft, referenceFrame: frame, panelSize: panel, margin: 20)
    #expect(origin.x == 20)
    #expect(origin.y == 430) // 500 - 50 - 20
}
```

**Step 4: Run tests**

Run: `make test`
Expected: All pass.

**Step 5: Commit**

```
feat: extract BeaconPositionCalculator from BeaconManager for testability
```

---

### Task 4: Make ITerm2Bridge types internal + test

**Files:**
- Modify: `juggler/Services/iTerm2Bridge.swift`
- Create: `JugglerTests/ITerm2BridgeTests.swift`

**Step 1: Change access control in `iTerm2Bridge.swift`**

Change `private struct DaemonRequest` → `struct DaemonRequest` (internal).
Change `private struct DaemonResponse` → `struct DaemonResponse` (internal).
Change `private struct DaemonEvent` → `struct DaemonEvent` (internal).
Change `private func shouldAttemptRecovery` → `func shouldAttemptRecovery` (internal).

**Step 2: Create `ITerm2BridgeTests.swift`**

```swift
import Foundation
@testable import Juggler
import Testing

// MARK: - DaemonRequest Encoding Tests

@Test func daemonRequest_encodesPingCommand() throws {
    let request = DaemonRequest(command: "ping")
    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["command"] as? String == "ping")
    #expect(json?["session_id"] == nil)
}

@Test func daemonRequest_encodesActivateWithSessionID() throws {
    let request = DaemonRequest(command: "activate", sessionID: "w0t0p0:abc")
    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["command"] as? String == "activate")
    #expect(json?["session_id"] as? String == "w0t0p0:abc")
}

@Test func daemonRequest_encodesHighlightWithConfigs() throws {
    let tab = HighlightConfig(enabled: true, color: [255, 0, 0], duration: 2.0)
    let request = DaemonRequest(command: "highlight", sessionID: "s1", tab: tab)
    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["tab"] != nil)
}

// MARK: - DaemonResponse Decoding Tests

@Test func daemonResponse_decodesOkStatus() throws {
    let json = #"{"status":"ok"}"#
    let response = try JSONDecoder().decode(DaemonResponse.self, from: Data(json.utf8))
    #expect(response.status == "ok")
    #expect(response.message == nil)
}

@Test func daemonResponse_decodesErrorWithMessage() throws {
    let json = #"{"status":"error","message":"not found"}"#
    let response = try JSONDecoder().decode(DaemonResponse.self, from: Data(json.utf8))
    #expect(response.status == "error")
    #expect(response.message == "not found")
}

@Test func daemonResponse_decodesSessionInfo() throws {
    let json = #"{"status":"ok","tab_name":"Tab 1","window_name":"Window","pane_index":0,"pane_count":2}"#
    let response = try JSONDecoder().decode(DaemonResponse.self, from: Data(json.utf8))
    #expect(response.tabName == "Tab 1")
    #expect(response.windowName == "Window")
    #expect(response.paneIndex == 0)
    #expect(response.paneCount == 2)
}

// MARK: - DaemonEvent Decoding Tests

@Test func daemonEvent_decodesFocusChanged() throws {
    let json = #"{"event":"focus_changed","session_id":"w0t0p0:abc"}"#
    let event = try JSONDecoder().decode(DaemonEvent.self, from: Data(json.utf8))
    #expect(event.event == "focus_changed")
    #expect(event.sessionID == "w0t0p0:abc")
}

@Test func daemonEvent_decodesTerminalInfo() throws {
    let json = #"{"event":"terminal_info","session_id":"s1","tab_name":"Tab","window_name":"Win","pane_index":1,"pane_count":3}"#
    let event = try JSONDecoder().decode(DaemonEvent.self, from: Data(json.utf8))
    #expect(event.event == "terminal_info")
    #expect(event.tabName == "Tab")
    #expect(event.windowName == "Win")
    #expect(event.paneIndex == 1)
    #expect(event.paneCount == 3)
}

@Test func daemonEvent_decodesMinimalEvent() throws {
    let json = #"{"event":"session_terminated"}"#
    let event = try JSONDecoder().decode(DaemonEvent.self, from: Data(json.utf8))
    #expect(event.event == "session_terminated")
    #expect(event.sessionID == nil)
}

// MARK: - shouldAttemptRecovery Tests

@Test func shouldAttemptRecovery_daemonNotRunning_returnsTrue() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.daemonNotRunning)
    #expect(result == true)
}

@Test func shouldAttemptRecovery_connectionFailed_returnsTrue() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.connectionFailed)
    #expect(result == true)
}

@Test func shouldAttemptRecovery_commandTimeout_returnsTrue() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.commandTimeout)
    #expect(result == true)
}

@Test func shouldAttemptRecovery_invalidResponse_returnsTrue() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.invalidResponse)
    #expect(result == true)
}

@Test func shouldAttemptRecovery_commandFailed_returnsFalse() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.commandFailed("test"))
    #expect(result == false)
}

@Test func shouldAttemptRecovery_authFailed_returnsFalse() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.authenticationFailed("test"))
    #expect(result == false)
}

@Test func shouldAttemptRecovery_sessionNotFound_returnsFalse() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.sessionNotFound("s1"))
    #expect(result == false)
}

@Test func shouldAttemptRecovery_bridgeNotAvailable_returnsFalse() async {
    let bridge = ITerm2Bridge.shared
    let result = await bridge.shouldAttemptRecovery(TerminalBridgeError.bridgeNotAvailable(.iterm2))
    #expect(result == false)
}

@Test func shouldAttemptRecovery_ioError_returnsTrue() async {
    let bridge = ITerm2Bridge.shared
    let error = NSError(domain: "test", code: 5, userInfo: [NSLocalizedDescriptionKey: "Input/output error"])
    let result = await bridge.shouldAttemptRecovery(error)
    #expect(result == true)
}

@Test func shouldAttemptRecovery_brokenPipe_returnsTrue() async {
    let bridge = ITerm2Bridge.shared
    let error = NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "Broken pipe"])
    let result = await bridge.shouldAttemptRecovery(error)
    #expect(result == true)
}

@Test func shouldAttemptRecovery_randomError_returnsFalse() async {
    let bridge = ITerm2Bridge.shared
    let error = NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "Something else"])
    let result = await bridge.shouldAttemptRecovery(error)
    #expect(result == false)
}
```

**Step 3: Run tests**

Run: `make test`
Expected: All pass.

**Step 4: Commit**

```
feat: expose ITerm2Bridge types for testability, add ITerm2BridgeTests
```

---

### Task 5: Make KittyBridge `rgbToHex` internal + test

**Files:**
- Modify: `juggler/Services/KittyBridge.swift`
- Expand: `JugglerTests/KittyBridgeTests.swift`

**Step 1: Change `private func rgbToHex` → `func rgbToHex` in KittyBridge.swift**

**Step 2: Add tests to `KittyBridgeTests.swift`**

```swift
// MARK: - rgbToHex Tests

@Test func rgbToHex_standardColor() async {
    let bridge = KittyBridge.shared
    let result = await bridge.rgbToHex([255, 128, 0])
    #expect(result == "#FF8000")
}

@Test func rgbToHex_black() async {
    let bridge = KittyBridge.shared
    let result = await bridge.rgbToHex([0, 0, 0])
    #expect(result == "#000000")
}

@Test func rgbToHex_white() async {
    let bridge = KittyBridge.shared
    let result = await bridge.rgbToHex([255, 255, 255])
    #expect(result == "#FFFFFF")
}

@Test func rgbToHex_tooFewElements_returnsFallback() async {
    let bridge = KittyBridge.shared
    let result = await bridge.rgbToHex([255])
    #expect(result == "#FF0000") // fallback
}

@Test func rgbToHex_emptyArray_returnsFallback() async {
    let bridge = KittyBridge.shared
    let result = await bridge.rgbToHex([])
    #expect(result == "#FF0000") // fallback
}
```

**Step 3: Run tests**

Run: `make test`
Expected: All pass.

**Step 4: Commit**

```
feat: expose KittyBridge.rgbToHex for testing, add rgbToHex tests
```

---

### Task 6: Deepen SessionManager tests

**Files:**
- Expand: `JugglerTests/SessionManagerTests.swift`

**Step 1: Add state transition + focus tests**

Add these tests to `SessionManagerTests.swift`:

```swift
// MARK: - updateFocusedSession Tests

@MainActor
@Test func updateFocusedSession_setsFocusedSessionID() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1")])

    manager.updateFocusedSession(terminalSessionID: "s1")

    #expect(manager.focusedSessionID == "s1")
}

@MainActor
@Test func updateFocusedSession_nil_clearsFocus() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1")])
    manager.updateFocusedSession(terminalSessionID: "s1")

    manager.updateFocusedSession(terminalSessionID: nil)

    #expect(manager.focusedSessionID == nil)
}

@MainActor
@Test func updateFocusedSession_bareUUID_notOverwriteComposite() {
    let manager = SessionManager()
    let session = Session(
        claudeSessionID: "c1", terminalSessionID: "w0t0p0:abc-uuid",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test", state: .idle, startedAt: Date()
    )
    manager.testSetSessions([session])

    // First set the composite ID as focused
    manager.updateFocusedSession(terminalSessionID: "w0t0p0:abc-uuid")
    #expect(manager.focusedSessionID == "w0t0p0:abc-uuid")

    // A bare UUID that's a substring shouldn't overwrite
    manager.updateFocusedSession(terminalSessionID: "abc-uuid")
    #expect(manager.focusedSessionID == "w0t0p0:abc-uuid") // preserved
}

@MainActor
@Test func updateFocusedSession_activationGuard_suppressesIntermediate() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1"), makeSession("s2")])

    manager.beginActivation(targetSessionID: "s2")
    manager.updateFocusedSession(terminalSessionID: "s1") // intermediate, should be suppressed

    #expect(manager.focusedSessionID == nil) // not set because it doesn't match target
}

@MainActor
@Test func updateFocusedSession_activationGuard_acceptsTarget() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1"), makeSession("s2")])

    manager.beginActivation(targetSessionID: "s2")
    manager.updateFocusedSession(terminalSessionID: "s2") // matches target

    #expect(manager.focusedSessionID == "s2")
}

@MainActor
@Test func endActivation_clearsGuard() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1")])

    manager.beginActivation(targetSessionID: "s1")
    manager.endActivation()
    manager.updateFocusedSession(terminalSessionID: "s1")

    #expect(manager.focusedSessionID == "s1")
}

// MARK: - isSessionFocused Tests

@MainActor
@Test func isSessionFocused_terminalActiveAndFocused_returnsTrue() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1")])
    manager.updateFocusedSession(terminalSessionID: "s1")
    // Simulate terminal app active
    manager.isTerminalAppActive = true

    #expect(manager.isSessionFocused == true)
}

@MainActor
@Test func isSessionFocused_terminalNotActive_returnsFalse() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1")])
    manager.updateFocusedSession(terminalSessionID: "s1")
    manager.isTerminalAppActive = false

    #expect(manager.isSessionFocused == false)
}

// MARK: - backburnerSession / reactivateSession Tests

@Test func backburnerSession_changesStateToBackburner() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .idle)])

    manager.backburnerSession(terminalSessionID: "s1")

    // State change is dispatched via Task, so check it was called
    // (the updateSessionState guards against same-state, so if idle→backburner it takes effect)
    #expect(manager.sessions.count == 1)
}

@Test func reactivateSession_changesStateToIdle() {
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .backburner)])

    manager.reactivateSession(terminalSessionID: "s1")

    #expect(manager.sessions.count == 1)
}

// MARK: - targetIndex Tests (via reorderForMode behavior)

@Test func reorderForMode_fair_permissionGroupedWithIdle() {
    let manager = SessionManager()
    manager.testSetSessions([
        makeSession("work1", state: .working),
        makeSession("perm1", state: .permission),
        makeSession("idle1", state: .idle),
    ])

    manager.reorderForMode(.fair)

    // Permission and idle are both in the "idle" group, before working
    let states = manager.sessions.map(\.state)
    let firstWorkingIdx = states.firstIndex(of: .working)!
    let idleTypes: Set<SessionState> = [.idle, .permission]
    for i in 0 ..< firstWorkingIdx {
        #expect(idleTypes.contains(states[i]))
    }
}

@Test func reorderForMode_fair_compactingGroupedWithWorking() {
    let manager = SessionManager()
    manager.testSetSessions([
        makeSession("idle1", state: .idle),
        makeSession("compact1", state: .compacting),
        makeSession("work1", state: .working),
        makeSession("back1", state: .backburner),
    ])

    manager.reorderForMode(.fair)

    // Order should be: idle, then working+compacting, then backburner
    #expect(manager.sessions[0].state == .idle)
    let midStates = Set([manager.sessions[1].state, manager.sessions[2].state])
    #expect(midStates == Set([.working, .compacting]))
    #expect(manager.sessions[3].state == .backburner)
}
```

**Step 2: Make `isTerminalAppActive` settable for tests**

In `SessionManager.swift`, the property `private(set) var isTerminalAppActive` needs to become `internal(set)` (or add a test helper). Since the file already has `testSetSessions`, add similarly:

```swift
// Change: private(set) var isTerminalAppActive = false
// To: internal(set) var isTerminalAppActive = false
```

**Step 3: Run tests**

Run: `make test`
Expected: All pass.

**Step 4: Commit**

```
test: deepen SessionManager coverage — focus, activation guard, backburner, reorder
```

---

### Task 7: Expand SessionListController tests

**Files:**
- Expand: `JugglerTests/SessionListControllerTests.swift`

**Step 1: Add tests for untested methods**

```swift
// MARK: - hasShortcutForKeyCode Tests

@Test func hasShortcutForKeyCode_matchingCode_returnsTrue() {
    let controller = SessionListController()
    // Default shortcuts include togglePause with keyCode 1 (S)
    #expect(controller.hasShortcutForKeyCode(1) == true)
}

@Test func hasShortcutForKeyCode_nonMatchingCode_returnsFalse() {
    let controller = SessionListController()
    // keyCode 999 is unlikely to match any shortcut
    #expect(controller.hasShortcutForKeyCode(999) == false)
}

// MARK: - backburnerSelected Tests

@Test func backburnerSelected_validIndex_backburners() {
    let controller = SessionListController()
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .idle), makeSession("s2", state: .idle)])

    controller.moveSelection(by: 1, sessionCount: 2) // select index 0
    controller.backburnerSelected(sessionManager: manager)

    // backburnerSession dispatches via Task, but the method should not crash
    #expect(manager.sessions.count == 2)
}

@Test func backburnerSelected_nilIndex_noOp() {
    let controller = SessionListController()
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1")])

    // selectedIndex is nil
    controller.backburnerSelected(sessionManager: manager)

    #expect(manager.sessions[0].state == .idle) // unchanged
}

// MARK: - reactivateSelected Tests

@Test func reactivateSelected_validIndex_reactivates() {
    let controller = SessionListController()
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .backburner)])

    controller.moveSelection(by: 1, sessionCount: 1) // select index 0
    controller.reactivateSelected(sessionManager: manager)

    #expect(manager.sessions.count == 1)
}

@Test func reactivateSelected_nilIndex_noOp() {
    let controller = SessionListController()
    let manager = SessionManager()
    manager.testSetSessions([makeSession("s1", state: .backburner)])

    controller.reactivateSelected(sessionManager: manager)

    #expect(manager.sessions[0].state == .backburner) // unchanged
}

// MARK: - renameSelected Tests

@Test func renameSelected_validIndex_setsSessionToRename() {
    let controller = SessionListController()
    let sessions = [makeSession("s1"), makeSession("s2")]

    controller.moveSelection(by: 1, sessionCount: 2) // select index 0
    controller.renameSelected(sessions: sessions)

    #expect(controller.sessionToRename?.terminalSessionID == "s1")
}

@Test func renameSelected_nilIndex_noOp() {
    let controller = SessionListController()
    let sessions = [makeSession("s1")]

    controller.renameSelected(sessions: sessions)

    #expect(controller.sessionToRename == nil)
}

// MARK: - trackSelectedSession Tests

@Test func trackSelectedSession_updatesInternalID() {
    let controller = SessionListController()
    let sessions = [makeSession("A"), makeSession("B")]

    controller.moveSelection(by: 1, sessionCount: 2) // → 0
    controller.trackSelectedSession(sessions: sessions)

    // Now reorder — syncSelection should find "A" by ID
    let reordered = [sessions[1], sessions[0]] // B, A
    controller.syncSelection(sessions: reordered)

    #expect(controller.selectedIndex == 1) // "A" moved to index 1
}
```

**Step 2: Run tests**

Run: `make test`
Expected: All pass.

**Step 3: Commit**

```
test: expand SessionListController coverage — shortcuts, backburner, rename, track
```

---

### Task 8: Expand HookServer processRequest tests

**Files:**
- Modify: `juggler/Services/HookServer.swift` (make `processRequest` internal)
- Expand: `JugglerTests/HookServerTests.swift`

**Step 1: Change access on `processRequest`**

In `HookServer.swift`, change:
```swift
private func processRequest(_ request: HTTPRequest) async -> HTTPResponse {
```
to:
```swift
func processRequest(_ request: HTTPRequest) async -> HTTPResponse {
```

Also change `private func decodeUnifiedPayload` to internal:
```swift
func decodeUnifiedPayload(_ body: String) -> UnifiedHookPayload? {
```

**Step 2: Add route dispatch tests to `HookServerTests.swift`**

```swift
// MARK: - processRequest Route Tests

@Test func processRequest_getNonPost_returns405() async {
    let server = HookServer()
    let request = HTTPRequest(method: "GET", path: "/hook", body: "")
    let response = await server.processRequest(request)
    #expect(response.status == 405)
}

@Test func processRequest_postUnknownPath_returns404() async {
    let server = HookServer()
    let request = HTTPRequest(method: "POST", path: "/unknown", body: "")
    let response = await server.processRequest(request)
    #expect(response.status == 404)
}

@Test func processRequest_postHook_invalidJSON_returns400() async {
    let server = HookServer()
    let request = HTTPRequest(method: "POST", path: "/hook", body: "not json")
    let response = await server.processRequest(request)
    #expect(response.status == 400)
}

@Test func processRequest_postHook_validPayload_returns200() async {
    let server = HookServer()
    let body = """
    {"agent":"claude-code","event":"Stop","terminal":{"sessionId":"s1","cwd":"/test","terminalType":"iterm2"}}
    """
    let request = HTTPRequest(method: "POST", path: "/hook", body: body)
    let response = await server.processRequest(request)
    #expect(response.status == 200)
}

@Test func processRequest_postKittyEvent_invalidJSON_returns400() async {
    let server = HookServer()
    let request = HTTPRequest(method: "POST", path: "/kitty-event", body: "bad")
    let response = await server.processRequest(request)
    #expect(response.status == 400)
}

@Test func processRequest_postKittyEvent_valid_returns200() async {
    let server = HookServer()
    let body = #"{"event":"focus_changed","window_id":"42"}"#
    let request = HTTPRequest(method: "POST", path: "/kitty-event", body: body)
    let response = await server.processRequest(request)
    #expect(response.status == 200)
}

@Test func processRequest_putMethod_returns405() async {
    let server = HookServer()
    let request = HTTPRequest(method: "PUT", path: "/hook", body: "{}")
    let response = await server.processRequest(request)
    #expect(response.status == 405)
}

// MARK: - decodeUnifiedPayload Tests

@Test func decodeUnifiedPayload_validMinimal_succeeds() async {
    let server = HookServer()
    let body = #"{"agent":"claude-code","event":"Stop"}"#
    let payload = await server.decodeUnifiedPayload(body)
    #expect(payload != nil)
    #expect(payload?.agent == "claude-code")
    #expect(payload?.event == "Stop")
}

@Test func decodeUnifiedPayload_withAllFields_succeeds() async {
    let server = HookServer()
    let body = """
    {"agent":"opencode","event":"session.created","hookInput":{"session_id":"abc","transcript_path":"/tmp/t.jsonl"},"terminal":{"sessionId":"s1","cwd":"/test","terminalType":"kitty","kittyListenOn":"unix:/tmp/kitty","kittyPid":"123"},"git":{"branch":"main","repo":"myrepo"},"tmux":{"pane":"%1","sessionName":"dev"}}
    """
    let payload = await server.decodeUnifiedPayload(body)
    #expect(payload != nil)
    #expect(payload?.agent == "opencode")
    #expect(payload?.hookInput?.sessionId == "abc")
    #expect(payload?.terminal?.kittyListenOn == "unix:/tmp/kitty")
    #expect(payload?.git?.branch == "main")
    #expect(payload?.tmux?.pane == "%1")
    #expect(payload?.tmux?.sessionName == "dev")
}

@Test func decodeUnifiedPayload_invalidJSON_returnsNil() async {
    let server = HookServer()
    let payload = await server.decodeUnifiedPayload("not json")
    #expect(payload == nil)
}
```

**Step 3: Run tests**

Run: `make test`
Expected: All pass.

**Step 4: Commit**

```
test: add HookServer processRequest route dispatch tests
```

---

### Task 9: Extract and test TerminalActivation highlight config builders

**Files:**
- Modify: `juggler/Services/TerminalBridge.swift`
- Create: `JugglerTests/TerminalActivationTests.swift`

**Step 1: Refactor highlight config builders to take explicit params**

In `TerminalBridge.swift`, add internal static methods that take explicit values:

```swift
// Add after the existing private static methods:
static func buildTabHighlightConfig(
    enabled: Bool,
    useCycling: Bool,
    colorIndex: Int,
    customColor: [Int],
    duration: Double
) -> HighlightConfig? {
    guard enabled else { return nil }
    let color = useCycling ? CyclingColors.paletteRGB[colorIndex % CyclingColors.paletteRGB.count] : customColor
    return HighlightConfig(enabled: true, color: color, duration: duration > 0 ? duration : 2.0)
}

static func buildPaneHighlightConfig(
    enabled: Bool,
    useCycling: Bool,
    colorIndex: Int,
    customColor: [Int],
    duration: Double
) -> HighlightConfig? {
    guard enabled else { return nil }
    let color = useCycling ? CyclingColors.darkPaletteRGB[colorIndex % CyclingColors.darkPaletteRGB.count] : customColor
    return HighlightConfig(enabled: true, color: color, duration: duration > 0 ? duration : 1.0)
}
```

Then update the private `tabHighlightConfig(for:)` and `paneHighlightConfig(for:)` to delegate to these.

**Step 2: Create `TerminalActivationTests.swift`**

```swift
import Foundation
@testable import Juggler
import Testing

// MARK: - buildTabHighlightConfig Tests

@Test func buildTabHighlight_disabled_returnsNil() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: false, useCycling: true, colorIndex: 0, customColor: [255, 0, 0], duration: 2.0
    )
    #expect(config == nil)
}

@Test func buildTabHighlight_cycling_usePaletteColor() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: true, useCycling: true, colorIndex: 0, customColor: [0, 0, 0], duration: 2.0
    )
    #expect(config != nil)
    #expect(config?.color == CyclingColors.paletteRGB[0])
    #expect(config?.duration == 2.0)
}

@Test func buildTabHighlight_notCycling_useCustomColor() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: true, useCycling: false, colorIndex: 0, customColor: [100, 200, 50], duration: 3.0
    )
    #expect(config?.color == [100, 200, 50])
}

@Test func buildTabHighlight_zeroDuration_defaultsToTwo() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: true, useCycling: false, colorIndex: 0, customColor: [0, 0, 0], duration: 0
    )
    #expect(config?.duration == 2.0)
}

@Test func buildTabHighlight_colorIndex_wraps() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: true, useCycling: true, colorIndex: 7, customColor: [0, 0, 0], duration: 1.0
    )
    // 7 % 5 = 2
    #expect(config?.color == CyclingColors.paletteRGB[2])
}

// MARK: - buildPaneHighlightConfig Tests

@Test func buildPaneHighlight_disabled_returnsNil() {
    let config = TerminalActivation.buildPaneHighlightConfig(
        enabled: false, useCycling: true, colorIndex: 0, customColor: [0, 0, 0], duration: 1.0
    )
    #expect(config == nil)
}

@Test func buildPaneHighlight_cycling_useDarkPalette() {
    let config = TerminalActivation.buildPaneHighlightConfig(
        enabled: true, useCycling: true, colorIndex: 0, customColor: [0, 0, 0], duration: 1.0
    )
    #expect(config?.color == CyclingColors.darkPaletteRGB[0])
}

@Test func buildPaneHighlight_zeroDuration_defaultsToOne() {
    let config = TerminalActivation.buildPaneHighlightConfig(
        enabled: true, useCycling: false, colorIndex: 0, customColor: [50, 50, 50], duration: 0
    )
    #expect(config?.duration == 1.0)
}
```

**Step 3: Run tests**

Run: `make test`
Expected: All pass.

**Step 4: Commit**

```
feat: extract TerminalActivation highlight config builders, add tests
```

---

### Task 10: Session model additional coverage

**Files:**
- Expand: `JugglerTests/JugglerTests.swift`

**Step 1: Add Session `title(for:)` and time computation tests**

```swift
// MARK: - Session title(for:) Tests

@Test func sessionTitle_tabTitle_prefersTmuxSessionName_forTmux() {
    var session = makeSession("s1")
    session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1", tmuxPane: "%1",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test/project", terminalTabName: "Tab",
        terminalWindowName: "Window", customName: nil,
        state: .idle, startedAt: Date()
    )
    // Need to set tmuxSessionName - it's a var
    var s = session
    s.tmuxSessionName = "dev-session"
    #expect(s.title(for: .tabTitle) == "dev-session")
}

@Test func sessionTitle_tabTitle_fallsBackToProjectFolder_forTmux() {
    var session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1", tmuxPane: "%1",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test/myproject", terminalTabName: "Tab",
        terminalWindowName: nil, customName: nil,
        state: .idle, startedAt: Date()
    )
    session.tmuxSessionName = nil
    #expect(session.title(for: .tabTitle) == "myproject")
}

@Test func sessionTitle_windowTitle_prefersWindowName() {
    var session = makeSession("s1")
    session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test/project", terminalTabName: "Tab",
        terminalWindowName: "My Window", customName: nil,
        state: .idle, startedAt: Date()
    )
    #expect(session.title(for: .windowTitle) == "My Window")
}

@Test func sessionTitle_windowAndTab_combinesNames() {
    let session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test/project", terminalTabName: "Tab 1",
        terminalWindowName: "Window 1", customName: nil,
        state: .idle, startedAt: Date()
    )
    #expect(session.title(for: .windowAndTabTitle) == "Window 1/Tab 1")
}

@Test func sessionTitle_windowAndTab_fallsBackToWindow() {
    let session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test/project", terminalTabName: nil,
        terminalWindowName: "Window", customName: nil,
        state: .idle, startedAt: Date()
    )
    #expect(session.title(for: .windowAndTabTitle) == "Window")
}

@Test func sessionTitle_customName_alwaysWins() {
    let session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test/project", terminalTabName: "Tab",
        terminalWindowName: "Window", customName: "My Custom Name",
        state: .idle, startedAt: Date()
    )
    #expect(session.title(for: .tabTitle) == "My Custom Name")
    #expect(session.title(for: .windowTitle) == "My Custom Name")
    #expect(session.title(for: .folderName) == "My Custom Name")
}

@Test func sessionTitle_parentAndFolder() {
    let session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/home/user/projects/myapp",
        state: .idle, startedAt: Date()
    )
    #expect(session.title(for: .parentAndFolderName) == "projects/myapp")
}

@Test func sessionTitle_parentAndFolder_shortPath() {
    let session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/myapp",
        state: .idle, startedAt: Date()
    )
    #expect(session.title(for: .parentAndFolderName) == "myapp")
}

// MARK: - Session fullDisplayName Tests

@Test func fullDisplayName_singlePane_noSuffix() {
    let session = makeSession("s1")
    #expect(session.fullDisplayName == session.displayName)
}

@Test func fullDisplayName_multiPane_showsIndex() {
    var session = makeSession("s1")
    session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test/project",
        state: .idle, startedAt: Date()
    )
    var s = session
    s.paneCount = 3
    s.paneIndex = 1
    #expect(s.fullDisplayName == "project (2/3)")
}

// MARK: - Session displayName priority Tests

@Test func displayName_tmuxPane_prefersCustomName() {
    var session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1", tmuxPane: "%1",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test/project", terminalTabName: "Tab",
        terminalWindowName: nil, customName: "Custom",
        state: .idle, startedAt: Date()
    )
    session.tmuxSessionName = "tmux-session"
    #expect(session.displayName == "Custom")
}

@Test func displayName_nonTmux_prefersTabName() {
    let session = Session(
        claudeSessionID: "c1", terminalSessionID: "s1",
        terminalType: .iterm2, agent: "claude-code",
        projectPath: "/test/project", terminalTabName: "My Tab",
        terminalWindowName: nil, customName: nil,
        state: .idle, startedAt: Date()
    )
    #expect(session.displayName == "My Tab")
}
```

**Step 2: Run tests**

Run: `make test`
Expected: All pass.

**Step 3: Commit**

```
test: add Session title modes, fullDisplayName, displayName priority tests
```

---

### Task 11: Final build + coverage check

**Step 1: Run lint and format**

Run: `make format && make lint`

**Step 2: Run full test suite**

Run: `make test`
Expected: All tests pass.

**Step 3: Check coverage**

Run: `make coverage`
Expected: Coverage increased significantly from 20.49%.

**Step 4: Commit any lint/format fixes**

```
chore: lint and format after test coverage increase
```

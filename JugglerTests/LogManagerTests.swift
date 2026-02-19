import Foundation
@testable import Juggler
import SwiftUI
import Testing

// MARK: - LogLevel Tests

@Test func logLevel_icon() {
    #expect(LogLevel.debug.icon == "ant")
    #expect(LogLevel.info.icon == "info.circle")
    #expect(LogLevel.warning.icon == "exclamationmark.triangle")
    #expect(LogLevel.error.icon == "xmark.circle")
}

@Test func logLevel_color() {
    #expect(LogLevel.debug.color == .gray)
    #expect(LogLevel.info.color == .blue)
    #expect(LogLevel.warning.color == .orange)
    #expect(LogLevel.error.color == .red)
}

// MARK: - LogCategory Tests

@Test func logCategory_allCases() {
    let cases = LogCategory.allCases
    #expect(cases.contains(.daemon))
    #expect(cases.contains(.hooks))
    #expect(cases.contains(.session))
    #expect(cases.contains(.hotkey))
    #expect(cases.contains(.kitty))
    #expect(cases.count == 5)
}

// MARK: - LogManager Tests

@MainActor
@Test func logManager_warningsAlwaysAdded() {
    let manager = LogManager.shared
    manager.clear()
    defer { manager.clear() }
    manager.verboseLogging = false

    manager.log(.warning, category: .session, "test warning")

    #expect(manager.entries.count == 1)
    #expect(manager.entries[0].level == .warning)
    #expect(manager.entries[0].message == "test warning")
}

@MainActor
@Test func logManager_errorsAlwaysAdded() {
    let manager = LogManager.shared
    manager.clear()
    defer { manager.clear() }
    manager.verboseLogging = false

    manager.log(.error, category: .daemon, "test error")

    #expect(manager.entries.count == 1)
    #expect(manager.entries[0].level == .error)
}

@MainActor
@Test func logManager_debugSkippedWithoutVerbose() {
    let manager = LogManager.shared
    manager.clear()
    manager.verboseLogging = false

    manager.log(.debug, category: .session, "debug msg")
    manager.log(.info, category: .session, "info msg")

    #expect(manager.entries.isEmpty)
}

@MainActor
@Test func logManager_debugAddedWithVerbose() {
    let manager = LogManager.shared
    manager.clear()
    defer { manager.clear(); manager.verboseLogging = false }
    manager.verboseLogging = true

    manager.log(.debug, category: .session, "debug msg")
    manager.log(.info, category: .hooks, "info msg")

    #expect(manager.entries.count == 2)
}

@MainActor
@Test func logManager_clear_emptiesEntries() {
    let manager = LogManager.shared
    manager.verboseLogging = false
    manager.log(.error, category: .daemon, "e1")
    manager.log(.warning, category: .daemon, "w1")

    manager.clear()

    #expect(manager.entries.isEmpty)
}

@MainActor
@Test func logManager_exportAll_formatsEntries() {
    let manager = LogManager.shared
    manager.clear()
    defer { manager.clear() }
    manager.verboseLogging = false

    manager.log(.error, category: .daemon, "export test")
    let output = manager.exportAll()

    #expect(output.contains("[ERROR]"))
    #expect(output.contains("[daemon]"))
    #expect(output.contains("export test"))
}

@MainActor
@Test func logManager_capsAt500Entries() {
    let manager = LogManager.shared
    manager.clear()
    defer { manager.clear() }
    manager.verboseLogging = false

    for i in 0 ..< 510 {
        manager.log(.error, category: .daemon, "entry \(i)")
    }

    #expect(manager.entries.count == 500)
    // Oldest entries should have been trimmed
    #expect(manager.entries.first?.message == "entry 10")
}

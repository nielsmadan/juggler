import Foundation
@testable import Juggler
import Testing

@Suite("QueueOrderMode")
struct QueueOrderModeTests {
    // MARK: - QueueOrderMode displayName Tests

    @Test func queueOrderMode_displayName() {
        #expect(QueueOrderMode.fair.displayName == "Fair")
        #expect(QueueOrderMode.prio.displayName == "Prio")
        #expect(QueueOrderMode.static.displayName == "Static")
        #expect(QueueOrderMode.grouped.displayName == "Grouped")
    }

    @Test func supportsPermissionPriority_onlyForDynamicModes() {
        #expect(QueueOrderMode.fair.supportsPermissionPriority)
        #expect(QueueOrderMode.prio.supportsPermissionPriority)
        #expect(!QueueOrderMode.static.supportsPermissionPriority)
        #expect(!QueueOrderMode.grouped.supportsPermissionPriority)
    }
}

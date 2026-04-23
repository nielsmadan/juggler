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
}

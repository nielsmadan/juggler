import Foundation
@testable import Juggler
import Testing

@Suite("SessionState")
struct SessionStateTests {
    // MARK: - SessionState displayText Tests

    @Test func sessionState_displayText() {
        #expect(SessionState.idle.displayText == "idle")
        #expect(SessionState.working.displayText == "working")
        #expect(SessionState.permission.displayText == "permission")
        #expect(SessionState.backburner.displayText == "backburner")
        #expect(SessionState.compacting.displayText == "compacting")
    }

    // MARK: - SessionState Codable Tests

    @Test func sessionState_codableRoundtrip() throws {
        for state in [SessionState.idle, .working, .permission, .backburner, .compacting] {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(SessionState.self, from: data)
            #expect(decoded == state)
        }
    }
}

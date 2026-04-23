import Foundation
@testable import Juggler
import Testing

@Suite("HighlightConfig")
struct HighlightConfigTests {
    // MARK: - HighlightConfig Tests

    @Test func highlightConfig_codableRoundtrip() throws {
        let config = HighlightConfig(enabled: true, color: [255, 128, 0], duration: 2.5)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(HighlightConfig.self, from: data)

        #expect(decoded.enabled == true)
        #expect(decoded.color == [255, 128, 0])
        #expect(decoded.duration == 2.5)
    }
}

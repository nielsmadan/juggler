import Foundation
@testable import Juggler
import Testing

@Suite("SessionStatsFormatter")
struct SessionStatsFormatterTests {
    // MARK: - formatDuration Tests

    @Test func formatDuration_zeroOrNegative_returnsZeroM() {
        #expect(SessionStatsFormatter.formatDuration(0) == "0m")
        #expect(SessionStatsFormatter.formatDuration(-5) == "0m")
    }

    @Test func formatDuration_underOneMinute_returnsLessThan1m() {
        #expect(SessionStatsFormatter.formatDuration(1) == "<1m")
        #expect(SessionStatsFormatter.formatDuration(30) == "<1m")
        #expect(SessionStatsFormatter.formatDuration(59) == "<1m")
    }

    @Test func formatDuration_minutes_returnsMinutes() {
        #expect(SessionStatsFormatter.formatDuration(60) == "1m")
        #expect(SessionStatsFormatter.formatDuration(120) == "2m")
        #expect(SessionStatsFormatter.formatDuration(3540) == "59m")
    }

    @Test func formatDuration_hours_zeroPadsMinutes() {
        #expect(SessionStatsFormatter.formatDuration(3600) == "1h00m")
        #expect(SessionStatsFormatter.formatDuration(3660) == "1h01m")
        #expect(SessionStatsFormatter.formatDuration(7500) == "2h05m")
        #expect(SessionStatsFormatter.formatDuration(82800) == "23h00m")
    }

    @Test func formatDuration_daysOrMore_dropsMinutes() {
        #expect(SessionStatsFormatter.formatDuration(86400) == "1d00h")
        #expect(SessionStatsFormatter.formatDuration(86400 + 12 * 3600) == "1d12h")
        #expect(SessionStatsFormatter.formatDuration(2 * 86400 + 3 * 3600 + 59 * 60) == "2d03h")
    }
}

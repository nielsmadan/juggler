//
//  SessionStatsCalculatorTests.swift
//  JugglerTests
//

import Foundation
@testable import Juggler
import Testing

@Suite("SessionStatsCalculator")
struct SessionStatsCalculatorTests {
    // MARK: - formatDuration Tests

    @Test func formatDuration_zeroOrNegative_returnsZeroM() {
        #expect(SessionStatsCalculator.formatDuration(0) == "0m")
        #expect(SessionStatsCalculator.formatDuration(-5) == "0m")
    }

    @Test func formatDuration_underOneMinute_returnsLessThan1m() {
        #expect(SessionStatsCalculator.formatDuration(1) == "<1m")
        #expect(SessionStatsCalculator.formatDuration(30) == "<1m")
        #expect(SessionStatsCalculator.formatDuration(59) == "<1m")
    }

    @Test func formatDuration_minutes_returnsMinutes() {
        #expect(SessionStatsCalculator.formatDuration(60) == "1m")
        #expect(SessionStatsCalculator.formatDuration(120) == "2m")
        #expect(SessionStatsCalculator.formatDuration(3540) == "59m")
    }

    @Test func formatDuration_hours_zeroPadsMinutes() {
        #expect(SessionStatsCalculator.formatDuration(3600) == "1h00m")
        #expect(SessionStatsCalculator.formatDuration(3660) == "1h01m")
        #expect(SessionStatsCalculator.formatDuration(7500) == "2h05m")
        #expect(SessionStatsCalculator.formatDuration(82800) == "23h00m")
    }

    @Test func formatDuration_daysOrMore_dropsMinutes() {
        #expect(SessionStatsCalculator.formatDuration(86400) == "1d00h")
        #expect(SessionStatsCalculator.formatDuration(86400 + 12 * 3600) == "1d12h")
        #expect(SessionStatsCalculator.formatDuration(2 * 86400 + 3 * 3600 + 59 * 60) == "2d03h")
    }
}

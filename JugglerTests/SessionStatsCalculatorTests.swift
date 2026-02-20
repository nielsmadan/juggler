//
//  SessionStatsCalculatorTests.swift
//  JugglerTests
//

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

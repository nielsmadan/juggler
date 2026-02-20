//
//  SessionStatsCalculator.swift
//  Juggler
//

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

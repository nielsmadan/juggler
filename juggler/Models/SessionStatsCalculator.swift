//
//  SessionStatsCalculator.swift
//  Juggler
//

import Foundation

/// Pure formatting helpers for session statistics.
enum SessionStatsCalculator {
    /// Human-readable duration:
    /// `0m` (exactly zero / negative), `<1m` (under a minute),
    /// `Xm` (under an hour), `XhYYm` (under a day, zero-padded minutes),
    /// `XdYYh` (a day or more, minutes dropped, zero-padded hours).
    static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "0m" }
        if seconds < 60 { return "<1m" }
        let totalMinutes = Int(seconds) / 60
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let totalHours = totalMinutes / 60
        if totalHours < 24 {
            return "\(totalHours)h\(String(format: "%02d", totalMinutes % 60))m"
        }
        let days = totalHours / 24
        return "\(days)d\(String(format: "%02d", totalHours % 24))h"
    }
}

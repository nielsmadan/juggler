//
//  LogManager.swift
//  Juggler
//

import Foundation
import SwiftUI

enum LogLevel: String, CaseIterable, Codable {
    case debug
    case info
    case warning
    case error

    var icon: String {
        switch self {
        case .debug: "ant"
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .debug: .gray
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}

enum LogCategory: String, CaseIterable {
    case daemon
    case hooks
    case session
    case hotkey
    case kitty
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
}

// MARK: - Development Debug Flags

// Flip these to enable Xcode console logging for specific categories during development
private let debugDaemon = false
private let debugHooks = false
private let debugSession = false
private let debugHotkey = false
private let debugKitty = false

@Observable
@MainActor
final class LogManager {
    static let shared = LogManager()

    private(set) var entries: [LogEntry] = []
    let maxEntries = 500

    @ObservationIgnored
    @AppStorage(AppStorageKeys.verboseLogging) var verboseLogging = false

    private init() {}

    func log(_ level: LogLevel, category: LogCategory, _ message: String) {
        // Xcode console: errors/warnings always, debug/info per category flag
        let shouldPrint: Bool = if level == .error || level == .warning {
            true
        } else {
            switch category {
            case .daemon: debugDaemon
            case .hooks: debugHooks
            case .session: debugSession
            case .hotkey: debugHotkey
            case .kitty: debugKitty
            }
        }

        if shouldPrint {
            print("[\(level.rawValue.uppercased())] [\(category.rawValue)] \(message)")
        }

        // In-app log window: errors/warnings always, debug/info if verbose enabled
        guard level == .error || level == .warning || verboseLogging else { return }

        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )

        entries.append(entry)

        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }

    func exportAll() -> String {
        entries.map { entry in
            let timestamp = entry.timestamp.formatted(date: .abbreviated, time: .standard)
            return "[\(timestamp)] [\(entry.level.rawValue.uppercased())] [\(entry.category.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
    }
}

@MainActor
func logDebug(_ category: LogCategory, _ message: String) {
    LogManager.shared.log(.debug, category: category, message)
}

@MainActor
func logInfo(_ category: LogCategory, _ message: String) {
    LogManager.shared.log(.info, category: category, message)
}

@MainActor
func logWarning(_ category: LogCategory, _ message: String) {
    LogManager.shared.log(.warning, category: category, message)
}

@MainActor
func logError(_ category: LogCategory, _ message: String) {
    LogManager.shared.log(.error, category: category, message)
}

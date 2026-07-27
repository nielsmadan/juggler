import Foundation

/// One day's busy-time total, as surfaced to the chart.
struct DailyBusyEntry: Identifiable, Equatable {
    let key: String // "yyyy-MM-dd" local-date key
    let date: Date // start-of-day in the current calendar
    let seconds: TimeInterval
    var id: String { key }
}

// Totals are summed across all sessions, so a day can exceed 24h.
@Observable
final class DailyStatsStore {
    private(set) var dailyBusySeconds: [String: TimeInterval]

    private let defaults: UserDefaults

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar.current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: AppStorageKeys.dailyBusyStats),
           let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            dailyBusySeconds = decoded
        } else {
            dailyBusySeconds = [:]
        }
    }

    static func dayKey(for date: Date) -> String {
        dateFormatter.string(from: date)
    }

    func addBusyTime(_ seconds: TimeInterval, on date: Date) {
        guard seconds > 0 else { return }
        dailyBusySeconds[Self.dayKey(for: date), default: 0] += seconds
        persist()
    }

    func busySeconds(for date: Date) -> TimeInterval {
        dailyBusySeconds[Self.dayKey(for: date)] ?? 0
    }

    var todayBusySeconds: TimeInterval {
        busySeconds(for: Date())
    }

    /// The most recent `limit` days that have data, oldest -> newest.
    func recentDays(limit: Int) -> [DailyBusyEntry] {
        let entries = dailyBusySeconds.compactMap { key, seconds -> DailyBusyEntry? in
            guard let date = Self.dateFormatter.date(from: key) else { return nil }
            return DailyBusyEntry(key: key, date: date, seconds: seconds)
        }
        .sorted { $0.key < $1.key } // "yyyy-MM-dd" sorts lexically == chronologically
        return Array(entries.suffix(max(0, limit)))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(dailyBusySeconds) {
            defaults.set(data, forKey: AppStorageKeys.dailyBusyStats)
        }
    }
}

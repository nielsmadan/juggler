import Foundation
@testable import Juggler
import Testing

@Suite("DailyStatsStore")
struct DailyStatsStoreTests {
    /// A throwaway UserDefaults suite so tests never touch real app data.
    private func freshStore() -> (DailyStatsStore, UserDefaults) {
        let suiteName = "DailyStatsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (DailyStatsStore(defaults: defaults), defaults)
    }

    @Test func addBusyTime_accumulatesPerDay() {
        let (store, _) = freshStore()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        store.addBusyTime(100, on: day)
        store.addBusyTime(50, on: day)
        #expect(store.busySeconds(for: day) == 150)
    }

    @Test func addBusyTime_ignoresNonPositiveValues() {
        let (store, _) = freshStore()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        store.addBusyTime(0, on: day)
        store.addBusyTime(-10, on: day)
        // A zero-time day never gets a map entry.
        #expect(store.busySeconds(for: day) == 0)
        #expect(store.dailyBusySeconds.isEmpty)
    }

    @Test func busySeconds_unknownDay_returnsZero() {
        let (store, _) = freshStore()
        #expect(store.busySeconds(for: Date()) == 0)
    }

    @Test func recentDays_returnsDaysWithDataOldestToNewest() {
        let (store, _) = freshStore()
        let cal = Calendar.current
        let d0 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let d1 = cal.date(byAdding: .day, value: 1, to: d0)!
        let d3 = cal.date(byAdding: .day, value: 3, to: d0)!
        // Add out of order; d2 intentionally has no data.
        store.addBusyTime(30, on: d3)
        store.addBusyTime(10, on: d0)
        store.addBusyTime(20, on: d1)

        let recent = store.recentDays(limit: 10)
        #expect(recent.count == 3)
        #expect(recent.map(\.seconds) == [10, 20, 30])
        #expect(recent[0].key == DailyStatsStore.dayKey(for: d0))
        #expect(recent[2].key == DailyStatsStore.dayKey(for: d3))
    }

    @Test func recentDays_respectsLimit() {
        let (store, _) = freshStore()
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        for offset in 0 ..< 10 {
            let day = cal.date(byAdding: .day, value: offset, to: base)!
            store.addBusyTime(Double(offset + 1), on: day)
        }
        let recent = store.recentDays(limit: 3)
        // Most recent 3 days, oldest -> newest.
        #expect(recent.map(\.seconds) == [8, 9, 10])
    }

    @Test func persistence_survivesReload() {
        let suiteName = "DailyStatsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let day = Date()

        let store1 = DailyStatsStore(defaults: defaults)
        store1.addBusyTime(123, on: day)

        // A second store reading the same defaults sees the persisted data.
        let store2 = DailyStatsStore(defaults: defaults)
        #expect(store2.busySeconds(for: day) == 123)
    }

    @Test func init_loadsArbitrarilyOldEntries() {
        // Historical entries are kept indefinitely — no retention/pruning.
        let suiteName = "DailyStatsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let cal = Calendar.current
        let veryOldDay = cal.date(byAdding: .day, value: -400, to: Date())!
        let seeded: [String: TimeInterval] = [DailyStatsStore.dayKey(for: veryOldDay): 999]
        let data = try! JSONEncoder().encode(seeded)
        defaults.set(data, forKey: AppStorageKeys.dailyBusyStats)

        let store = DailyStatsStore(defaults: defaults)
        #expect(store.busySeconds(for: veryOldDay) == 999)
    }
}

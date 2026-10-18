import Foundation

/// hooklinesinker bindings the user removed, so hydration can hide them until they report new activity.
final class HiddenBindingStore {
    private var hiddenAt: [String: Date]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: AppStorageKeys.hiddenSessionBindings),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            hiddenAt = decoded
        } else {
            hiddenAt = [:]
        }
    }

    func hide(_ bindingIDs: Set<String>, at date: Date) {
        guard !bindingIDs.isEmpty else { return }
        for bindingID in bindingIDs {
            hiddenAt[bindingID] = date
        }
        persist()
    }

    func reveal(_ bindingID: String) {
        guard hiddenAt.removeValue(forKey: bindingID) != nil else { return }
        persist()
    }

    func revealAll() {
        guard !hiddenAt.isEmpty else { return }
        hiddenAt = [:]
        persist()
    }

    func prune(keeping bindingIDs: Set<String>) {
        let kept = hiddenAt.filter { bindingIDs.contains($0.key) }
        guard kept.count != hiddenAt.count else { return }
        hiddenAt = kept
        persist()
    }

    /// A record without a readable time cannot prove activity after the removal, so it stays hidden.
    func hides(_ bindingID: String, observedAt: Date?) -> Bool {
        guard let hiddenSince = hiddenAt[bindingID] else { return false }
        guard let observedAt else { return true }
        return observedAt <= hiddenSince
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(hiddenAt) {
            defaults.set(data, forKey: AppStorageKeys.hiddenSessionBindings)
        }
    }
}

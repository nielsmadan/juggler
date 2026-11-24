import Foundation

struct SessionNameRecord: Codable, Equatable {
    let key: SessionNoteKey
    let name: String
}

final class SessionNameStore {
    private(set) var names: [SessionNoteKey: String]
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        guard let data = defaults?.data(forKey: AppStorageKeys.sessionCustomNames) else {
            names = [:]
            return
        }
        do {
            let records = try JSONDecoder().decode([SessionNameRecord].self, from: data)
            names = records.reduce(into: [:]) { result, record in
                if record.key.isPersistent, let name = SessionNoteStore.normalize(record.name) {
                    result[record.key] = name
                }
            }
        } catch {
            names = [:]
            let message = String(describing: error)
            Task { @MainActor in
                logError(.session, "Failed to decode session custom names: \(message)")
            }
        }
    }

    func name(for key: SessionNoteKey) -> String? {
        guard key.isPersistent else { return nil }
        return names[key]
    }

    @discardableResult
    func setName(_ name: String?, for key: SessionNoteKey) -> String? {
        guard key.isPersistent else { return nil }
        let normalized = SessionNoteStore.normalize(name)
        guard names[key] != normalized else { return normalized }
        if let normalized {
            names[key] = normalized
        } else {
            names.removeValue(forKey: key)
        }
        persist()
        return normalized
    }

    private func persist() {
        guard let defaults else { return }
        let records = names.map { SessionNameRecord(key: $0.key, name: $0.value) }
            .sorted {
                ($0.key.agent, $0.key.agentSessionID) < ($1.key.agent, $1.key.agentSessionID)
            }
        do {
            try defaults.set(JSONEncoder().encode(records), forKey: AppStorageKeys.sessionCustomNames)
        } catch {
            let message = String(describing: error)
            Task { @MainActor in
                logError(.session, "Failed to encode session custom names: \(message)")
            }
        }
    }
}

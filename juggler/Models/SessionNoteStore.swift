import Foundation

nonisolated struct AgentSessionIdentity: Hashable, Codable {
    let agent: String
    let agentSessionID: String

    var isPersistent: Bool {
        [agent, agentSessionID].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.rangeOfCharacter(from: .controlCharacters) == nil
        }
    }
}

typealias SessionNoteKey = AgentSessionIdentity

struct SessionNoteRecord: Codable, Equatable {
    let key: SessionNoteKey
    let note: String
}

final class SessionNoteStore {
    private(set) var notes: [SessionNoteKey: String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: AppStorageKeys.sessionNotes) else {
            notes = [:]
            return
        }
        do {
            let records = try JSONDecoder().decode([SessionNoteRecord].self, from: data)
            notes = records.reduce(into: [:]) { result, record in
                if record.key.isPersistent, let note = Self.normalize(record.note) {
                    result[record.key] = note
                }
            }
        } catch {
            notes = [:]
            let message = String(describing: error)
            Task { @MainActor in
                logError(.session, "Failed to decode session notes: \(message)")
            }
        }
    }

    func note(for key: SessionNoteKey) -> String? {
        guard key.isPersistent else { return nil }
        return notes[key]
    }

    @discardableResult
    func setNote(_ note: String?, for key: SessionNoteKey) -> String? {
        guard key.isPersistent else { return nil }
        let normalized = Self.normalize(note)
        guard notes[key] != normalized else { return normalized }
        if let normalized {
            notes[key] = normalized
        } else {
            notes.removeValue(forKey: key)
        }
        persist()
        return normalized
    }

    static func normalize(_ note: String?) -> String? {
        guard let note else { return nil }
        let line = note.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }

    private func persist() {
        let records = notes.map { SessionNoteRecord(key: $0.key, note: $0.value) }
            .sorted {
                ($0.key.agent, $0.key.agentSessionID) < ($1.key.agent, $1.key.agentSessionID)
            }
        do {
            try defaults.set(JSONEncoder().encode(records), forKey: AppStorageKeys.sessionNotes)
        } catch {
            let message = String(describing: error)
            Task { @MainActor in
                logError(.session, "Failed to encode session notes: \(message)")
            }
        }
    }
}

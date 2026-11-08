import Foundation

nonisolated struct SessionDispositionRecord: Codable, Equatable {
    let key: AgentSessionIdentity
    let disposition: SessionDisposition

    init(key: AgentSessionIdentity, disposition: SessionDisposition) {
        self.key = key
        self.disposition = disposition
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(AgentSessionIdentity.self, forKey: .key)
        disposition = try container.decode(SessionDisposition.self, forKey: .disposition)
    }
}

nonisolated struct SessionDispositionEnvelope: Codable, Equatable {
    static let currentVersion = 1

    let schemaVersion: Int
    let records: [SessionDispositionRecord]

    init(schemaVersion: Int = Self.currentVersion, records: [SessionDispositionRecord]) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        var encodedRecords = try container.nestedUnkeyedContainer(forKey: .records)
        var decoded: [SessionDispositionRecord] = []
        while !encodedRecords.isAtEnd {
            let recordDecoder = try encodedRecords.superDecoder()
            if let record = try? SessionDispositionRecord(from: recordDecoder) { decoded.append(record) }
        }
        records = decoded
    }
}

final class SessionDispositionStore {
    private(set) var dispositions: [AgentSessionIdentity: SessionDisposition] = [:]
    private let defaults: UserDefaults?
    private let reportError: (String) -> Void

    init(defaults: UserDefaults? = nil, reportError: @escaping (String) -> Void = { message in
        Task { @MainActor in logError(.session, message) }
    }) {
        self.defaults = defaults
        self.reportError = reportError
        guard let data = defaults?.data(forKey: AppStorageKeys.sessionDispositions) else { return }
        do {
            let envelope = try JSONDecoder().decode(SessionDispositionEnvelope.self, from: data)
            guard envelope.schemaVersion == SessionDispositionEnvelope.currentVersion else {
                reportError("Unsupported session disposition schema: \(envelope.schemaVersion)")
                return
            }
            for record in envelope.records where record.key.isPersistent {
                // The last valid record wins, including an empty record that clears an earlier value.
                dispositions[record.key] = record.disposition == .empty ? nil : record.disposition
            }
        } catch {
            reportError("Failed to decode session dispositions: \(error)")
        }
    }

    func disposition(for key: AgentSessionIdentity) -> SessionDisposition {
        guard key.isPersistent else { return .empty }
        return dispositions[key] ?? .empty
    }

    func setDisposition(_ disposition: SessionDisposition, for key: AgentSessionIdentity) {
        guard key.isPersistent, self.disposition(for: key) != disposition else { return }
        dispositions[key] = disposition == .empty ? nil : disposition
        persist()
    }

    func clear() {
        dispositions = [:]
        persist()
    }

    private func persist() {
        guard let defaults else { return }
        let records = dispositions.map { SessionDispositionRecord(key: $0.key, disposition: $0.value) }
            .sorted { ($0.key.agent, $0.key.agentSessionID) < ($1.key.agent, $1.key.agentSessionID) }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(SessionDispositionEnvelope(records: records))
            defaults.set(data, forKey: AppStorageKeys.sessionDispositions)
        } catch {
            reportError("Failed to encode session dispositions: \(error)")
        }
    }
}

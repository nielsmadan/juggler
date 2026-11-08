import Foundation

nonisolated struct SessionNotificationTarget: Codable, Equatable, Sendable {
    let sessionID: String
    let identity: AgentSessionIdentity?
    let token: UUID
    let sequence: UInt64

    var userInfo: [String: String] {
        guard let data = try? JSONEncoder().encode(self), let json = String(data: data, encoding: .utf8) else {
            return [:]
        }
        return ["sessionTarget": json]
    }

    init(sessionID: String, identity: AgentSessionIdentity?, token: UUID, sequence: UInt64) {
        self.sessionID = sessionID
        self.identity = identity
        self.token = token
        self.sequence = sequence
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let json = userInfo["sessionTarget"] as? String,
              let target = try? JSONDecoder().decode(Self.self, from: Data(json.utf8)) else { return nil }
        self = target
    }
}

import Foundation

nonisolated struct BackburnerDisposition: Codable, Equatable {
    let wasAwaitingUser: Bool
    let backburneredAt: Date
    let turnsByBinding: [String: Int]

    init(wasAwaitingUser: Bool, backburneredAt: Date, turnsByBinding: [String: Int] = [:]) {
        self.wasAwaitingUser = wasAwaitingUser
        self.backburneredAt = backburneredAt
        self.turnsByBinding = turnsByBinding.filter { !$0.key.isEmpty && $0.value >= 0 }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wasAwaitingUser = try container.decode(Bool.self, forKey: .wasAwaitingUser)
        backburneredAt = try container.decode(Date.self, forKey: .backburneredAt)
        let counts = (try? container.decode([String: DecodedTurnCount].self, forKey: .turnsByBinding)) ?? [:]
        turnsByBinding = counts.compactMapValues(\.value).filter { !$0.key.isEmpty }
    }

    private struct DecodedTurnCount: Decodable {
        let value: Int?

        init(from decoder: any Decoder) throws {
            let count = try? decoder.singleValueContainer().decode(Int.self)
            value = count.flatMap { $0 >= 0 ? $0 : nil }
        }
    }
}

nonisolated struct SessionDisposition: Codable, Equatable {
    var isHidden: Bool
    var isPrioritized: Bool
    var backburner: BackburnerDisposition?

    static let empty = SessionDisposition(isHidden: false, backburner: nil)

    init(isHidden: Bool, isPrioritized: Bool = false, backburner: BackburnerDisposition? = nil) {
        self.isHidden = isHidden
        self.isPrioritized = isPrioritized
        self.backburner = backburner
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isHidden = try container.decode(Bool.self, forKey: .isHidden)
        isPrioritized = try container.decodeIfPresent(Bool.self, forKey: .isPrioritized) ?? false
        backburner = try container.decodeIfPresent(BackburnerDisposition.self, forKey: .backburner)
    }
}

nonisolated struct TransientDispositionOverrides: Equatable {
    enum Backburner: Equatable {
        case unchanged
        case set(BackburnerDisposition?)
    }

    var isHidden: Bool?
    var isPrioritized: Bool?
    var backburner: Backburner = .unchanged

    func applying(to stored: SessionDisposition) -> SessionDisposition {
        var result = stored
        if let isHidden { result.isHidden = isHidden }
        if let isPrioritized { result.isPrioritized = isPrioritized }
        if case let .set(backburner) = backburner { result.backburner = backburner }
        return result
    }
}

enum SessionIdentityTransition: Equatable {
    case unchanged
    case filledMissing(previous: AgentSessionIdentity, current: AgentSessionIdentity)
    case replaced(previous: AgentSessionIdentity, current: AgentSessionIdentity)
    case rejected

    static func resolve(
        current: AgentSessionIdentity,
        incoming: AgentSessionIdentity,
        event: String?
    ) -> Self {
        if current == incoming || (current.agent == incoming.agent && incoming.agentSessionID.isEmpty) {
            return .unchanged
        }
        if current.agent == incoming.agent, !current.isPersistent, incoming.isPersistent {
            return .filledMissing(previous: current, current: incoming)
        }
        let establishesIdentity = event.map {
            HookEventMapper.establishesSessionIdentity(event: $0, agent: incoming.agent)
        } ?? true
        return establishesIdentity ? .replaced(previous: current, current: incoming) : .rejected
    }
}

extension BackburnerDisposition {
    func shouldWake(agent: String, state: SessionState, event: String?, source: StatusSource,
                    details: SessionDetails, bindingID: String?) -> Bool {
        let isAntigravityResume = agent == "antigravity" && wasAwaitingUser && state == .working
        if source == .live { return event == "UserPromptSubmit" || isAntigravityResume }
        guard let observedAt = details.observedAt, observedAt > backburneredAt else { return false }
        if let bindingID, let baseline = turnsByBinding[bindingID],
           let turns = details.reportedTurns, turns > baseline { return true }
        return event == "UserPromptSubmit" || isAntigravityResume
    }
}

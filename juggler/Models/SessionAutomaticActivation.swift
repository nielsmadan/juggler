import Foundation

nonisolated struct SessionAutomaticActivation: Sendable {
    enum Kind: Sendable {
        case advance
        case restart
    }

    let kind: Kind
    let sourceID: String
    let sourceIdentity: AgentSessionIdentity
    let sourceToken: UUID
    let contextToken: UUID
}

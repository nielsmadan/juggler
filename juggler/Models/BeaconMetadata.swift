import Foundation

struct BeaconMetadata: Equatable {
    let subtitle: String?

    static func resolve(for target: Session, among sessions: [Session]) -> BeaconMetadata {
        let includeTerminal = Set(sessions.map(\.terminalType)).count > 1
        let includeAgent = Set(sessions.map(\.agent)).count > 1
        let components = [
            includeTerminal ? target.terminalType.displayName : nil,
            includeAgent ? target.agentDisplayName : nil
        ].compactMap { $0 }

        return BeaconMetadata(subtitle: components.isEmpty ? nil : components.joined(separator: " · "))
    }
}

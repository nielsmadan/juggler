import Foundation

enum SessionState: String, Codable, CaseIterable {
    case working // Claude is working
    case idle // Waiting for user input
    case permission // Waiting for user permission
    case backburner // Manually deprioritized
    case compacting // Claude is compacting context

    var isIncludedInCycle: Bool {
        switch self {
        case .idle, .permission:
            true
        case .working, .backburner, .compacting:
            false
        }
    }

    var displayText: String {
        switch self {
        case .working: "working"
        case .idle: "idle"
        case .permission: "permission"
        case .backburner: "backburner"
        case .compacting: "compacting"
        }
    }

    var iconName: String {
        switch self {
        case .idle, .permission: "figure.wave"
        case .working: "figure.run"
        case .backburner: "moon.zzz"
        case .compacting: "arrow.3.trianglepath"
        }
    }
}

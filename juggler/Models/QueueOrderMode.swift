import Foundation

enum QueueOrderMode: String, CaseIterable {
    case fair // Return-to-idle goes to end (round-robin)
    case prio // Return-to-idle goes to top (most recent first)
    case `static` // No reordering

    var displayName: String {
        switch self {
        case .fair: "Fair"
        case .prio: "Prio"
        case .static: "Static"
        }
    }
}

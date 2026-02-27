import Foundation

enum QueueOrderMode: String, CaseIterable {
    case fair // Return-to-idle goes to end (round-robin)
    case prio // Return-to-idle goes to top (most recent first)
    case `static`
    case grouped // Grouped by terminal window

    static let `default`: QueueOrderMode = .fair

    var displayName: String {
        switch self {
        case .fair: "Fair"
        case .prio: "Prio"
        case .static: "Static"
        case .grouped: "Grouped"
        }
    }

    var helpText: String {
        switch self {
        case .fair: "Idle sessions go to end of queue"
        case .prio: "Idle sessions go to top of queue"
        case .static: "No automatic reordering"
        case .grouped: "Static + grouped by window"
        }
    }
}

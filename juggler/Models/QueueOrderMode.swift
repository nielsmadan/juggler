import Foundation

enum QueueOrderMode: String, CaseIterable {
    case fair
    case prio
    case `static`
    case grouped

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

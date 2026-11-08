enum SessionListEmptyState {
    case noSessions
    case allHidden

    var title: String {
        switch self {
        case .noSessions: "No Sessions"
        case .allHidden: "All Sessions Hidden"
        }
    }

    var icon: String {
        switch self {
        case .noSessions: "terminal"
        case .allHidden: "eye.slash"
        }
    }

    var description: String {
        switch self {
        case .noSessions:
            "Start or continue a session and it will show up here.\n\nCodex and Antigravity sessions appear after your first message."
        case .allHidden:
            "Turn on Show Hidden in Session Monitor to see these sessions."
        }
    }
}

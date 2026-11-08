enum SessionRowAction: CaseIterable {
    case rename
    case note
    case hide

    static func visible(rename: Bool, note: Bool, hide: Bool) -> [Self] {
        [(Self.rename, rename), (.note, note), (.hide, hide)].compactMap { $0.1 ? $0.0 : nil }
    }

    func icon(for session: Session) -> String {
        switch self {
        case .rename: "pencil"
        case .note: session.note == nil ? "text.bubble" : "text.bubble.fill"
        case .hide: session.isHidden ? "eye" : "eye.slash"
        }
    }

    func label(for session: Session) -> String {
        switch self {
        case .rename: "Rename session"
        case .note: session.note == nil ? "Add note" : "Edit note"
        case .hide: session.isHidden ? "Unhide session" : "Hide session"
        }
    }
}

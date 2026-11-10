enum SessionRowAction: String, CaseIterable {
    case rename
    case note
    case hide
    case prio

    static func storageValue(for action: SessionRowAction?) -> String {
        action?.rawValue ?? "none"
    }

    func isAvailable(in mode: QueueOrderMode?) -> Bool {
        self != .prio || mode?.supportsPrioritizedSessions == true
    }

    var displayName: String {
        switch self {
        case .rename: "Rename"
        case .note: "Note"
        case .hide: "Hide"
        case .prio: "Prio"
        }
    }

    func icon(for session: Session) -> String {
        switch self {
        case .rename: "pencil"
        case .note: session.note == nil ? "text.bubble" : "text.bubble.fill"
        case .hide: session.isHidden ? "eye" : "eye.slash"
        case .prio: session.isPrioritized ? "flag.fill" : "flag"
        }
    }

    func label(for session: Session) -> String {
        switch self {
        case .rename: "Rename session"
        case .note: session.note == nil ? "Add note" : "Edit note"
        case .hide: session.isHidden ? "Unhide session" : "Hide session"
        case .prio: session.isPrioritized ? "Unprioritize session" : "Prioritize session"
        }
    }
}

enum RowActionPosition: CaseIterable {
    case first
    case second
    case third

    static var registrationDefaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.storageKey, $0.defaultAction.rawValue) })
    }

    var title: String {
        switch self {
        case .first: "Action 1"
        case .second: "Action 2"
        case .third: "Action 3"
        }
    }

    var storageKey: String {
        switch self {
        case .first: AppStorageKeys.monitorRowActionFirst
        case .second: AppStorageKeys.monitorRowActionSecond
        case .third: AppStorageKeys.monitorRowActionThird
        }
    }

    var defaultAction: SessionRowAction {
        switch self {
        case .first: .rename
        case .second: .note
        case .third: .hide
        }
    }

    fileprivate var legacyVisibilityKey: String {
        switch self {
        case .first: AppStorageKeys.monitorShowRenameButton
        case .second: AppStorageKeys.monitorShowNoteButton
        case .third: AppStorageKeys.monitorShowHideButton
        }
    }
}

enum RowActionMigration {
    static func pendingValues(stored: (String) -> Any?) -> [String: String] {
        guard RowActionPosition.allCases.allSatisfy({ stored($0.storageKey) == nil }) else { return [:] }
        return Dictionary(uniqueKeysWithValues: RowActionPosition.allCases.map { position in
            let isVisible = stored(position.legacyVisibilityKey) as? Bool ?? true
            return (position.storageKey, SessionRowAction.storageValue(for: isVisible ? position.defaultAction : nil))
        })
    }
}

import Foundation

enum RowSlot: String, CaseIterable, Sendable {
    case none
    case folderPath
    case folderName
    case parentAndFolderName
    case tabTitle
    case windowTitle
    case agentTitle
    case gitBranch
    case model
    case effort
    case permissionMode
    case currentTool
    case lastProblem
    case subagents
    case contextPercent
    case turns
    case runTime

    var displayName: String {
        switch self {
        case .none: "None"
        case .folderPath: "Folder Path"
        case .folderName: "Folder Name"
        case .parentAndFolderName: "Parent / Folder Name"
        case .tabTitle: "Tab Title"
        case .windowTitle: "Window Title"
        case .agentTitle: "Agent Session Title"
        case .gitBranch: "Git Branch"
        case .model: "Model"
        case .effort: "Effort"
        case .permissionMode: "Permission Mode"
        case .currentTool: "Current Tool"
        case .lastProblem: "Last Problem"
        case .subagents: "Subagents"
        case .contextPercent: "Context %"
        case .turns: "Turns"
        case .runTime: "Run Time"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "minus"
        case .folderPath: "folder"
        case .folderName: "folder.fill"
        case .parentAndFolderName: "folder.badge.plus"
        case .tabTitle: "rectangle.topthird.inset.filled"
        case .windowTitle: "macwindow"
        case .agentTitle: "text.bubble"
        case .gitBranch: "arrow.triangle.branch"
        case .model: "cpu"
        case .effort: "gauge.with.dots.needle.50percent"
        case .permissionMode: "lock.shield"
        case .currentTool: "wrench.and.screwdriver"
        case .lastProblem: "exclamationmark.triangle"
        case .subagents: "person.2"
        case .contextPercent: "chart.pie"
        case .turns: "arrow.triangle.2.circlepath"
        case .runTime: "clock"
        }
    }

    func value(for session: Session, now: Date, abbreviateHome: Bool) -> String? {
        switch self {
        case .none:
            nil
        case .folderPath:
            abbreviateHome ? HomePathFormatter.abbreviate(session.projectPath) : session.projectPath
        case .folderName:
            session.projectFolderName
        case .parentAndFolderName:
            session.parentAndFolderName
        case .tabTitle:
            session.terminalTabName.nonEmpty
        case .windowTitle:
            session.terminalWindowName.nonEmpty
        case .agentTitle:
            session.details.agentTitle.nonEmpty
        case .gitBranch:
            session.gitBranch.nonEmpty
        case .model, .effort, .permissionMode, .currentTool, .lastProblem, .subagents, .contextPercent, .turns,
             .runTime:
            detailValue(details: session.details, turnCount: session.turnCount, now: now)
        }
    }

    private func detailValue(details: SessionDetails, turnCount: Int, now: Date) -> String? {
        switch self {
        case .model:
            details.model.nonEmpty
        case .effort:
            details.effort.nonEmpty
        case .permissionMode:
            details.permissionMode.nonEmpty.map(RowSlotLabels.permissionMode)
        case .currentTool:
            details.currentTool.nonEmpty
        case .lastProblem:
            details.lastProblem.nonEmpty.map(RowSlotLabels.problem)
        case .subagents:
            RowSlotLabels.count(details.subagentCount, singular: "subagent", plural: "subagents")
        case .contextPercent:
            details.contextPercent.map { "\($0)% context" }
        case .turns:
            RowSlotLabels.count(details.turns ?? turnCount, singular: "turn", plural: "turns")
        case .runTime:
            details.processStartedAt.map { SessionStatsFormatter.formatDuration(now.timeIntervalSince($0)) }
        case .none, .folderPath, .folderName, .parentAndFolderName, .tabTitle, .windowTitle, .agentTitle,
             .gitBranch:
            nil
        }
    }
}

enum RowSlotLabels {
    private static let permissionModes = [
        "default": "Default",
        "plan": "Plan",
        "acceptEdits": "Accept Edits",
        "bypassPermissions": "Bypass",
        "auto": "Auto",
        "dontAsk": "Don't Ask"
    ]

    private static let problems = [
        "rate_limit": "Rate limited",
        "rate_limit_error": "Rate limited",
        "overloaded": "Overloaded",
        "overloaded_error": "Overloaded",
        "billing_error": "Billing error",
        "authentication_failed": "Auth failed",
        "max_output_tokens": "Output limit",
        "max_steps_exceeded": "Step limit",
        "interrupted": "Interrupted",
        "error": "Error"
    ]

    static func permissionMode(_ mode: String) -> String {
        if let label = permissionModes[mode] { return label }
        return mode
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { capitalizedFirst(String($0)) }
            .joined(separator: " ")
    }

    static func problem(_ token: String) -> String {
        problems[token] ?? capitalizedFirst(token.replacingOccurrences(of: "_", with: " "))
    }

    static func count(_ value: Int, singular: String, plural: String) -> String? {
        guard value > 0 else { return nil }
        return "\(value) \(value == 1 ? singular : plural)"
    }

    private static func capitalizedFirst(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }
}

enum RowSlotPosition: String, CaseIterable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var title: String {
        switch self {
        case .topLeading: "Top left"
        case .topTrailing: "Top right"
        case .bottomLeading: "Bottom left"
        case .bottomTrailing: "Bottom right"
        }
    }

    var storageKey: String {
        switch self {
        case .topLeading: AppStorageKeys.monitorSlotTopLeading
        case .topTrailing: AppStorageKeys.monitorSlotTopTrailing
        case .bottomLeading: AppStorageKeys.monitorSlotBottomLeading
        case .bottomTrailing: AppStorageKeys.monitorSlotBottomTrailing
        }
    }

    var defaultSlot: RowSlot {
        switch self {
        case .topLeading: .folderPath
        case .topTrailing: .model
        case .bottomLeading: .gitBranch
        case .bottomTrailing: .effort
        }
    }

    static var registrationDefaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.storageKey, $0.defaultSlot.rawValue) })
    }
}

struct ResolvedSlot: Equatable {
    let slot: RowSlot
    let text: String?
}

struct ResolvedSlotRow: Equatable {
    let leading: ResolvedSlot?
    let trailing: ResolvedSlot?
}

struct ResolvedSlotGrid: Equatable {
    var top: ResolvedSlotRow?
    var bottom: ResolvedSlotRow?

    static func resolve(
        _ slots: [RowSlotPosition: RowSlot],
        session: Session,
        now: Date,
        abbreviateHome: Bool
    ) -> ResolvedSlotGrid {
        func cell(_ position: RowSlotPosition) -> ResolvedSlot? {
            let slot = slots[position] ?? .none
            guard slot != .none else { return nil }
            return ResolvedSlot(slot: slot, text: slot.value(for: session, now: now, abbreviateHome: abbreviateHome))
        }
        func row(_ leading: RowSlotPosition, _ trailing: RowSlotPosition) -> ResolvedSlotRow? {
            let leadingCell = cell(leading)
            let trailingCell = cell(trailing)
            guard leadingCell != nil || trailingCell != nil else { return nil }
            return ResolvedSlotRow(leading: leadingCell, trailing: trailingCell)
        }
        return ResolvedSlotGrid(
            top: row(.topLeading, .topTrailing),
            bottom: row(.bottomLeading, .bottomTrailing)
        )
    }
}

enum RowSlotMigration {
    static func slots(showFolderPath: Bool?, showBranch: Bool?) -> [RowSlotPosition: RowSlot] {
        let folder = showFolderPath ?? true
        let branch = showBranch ?? true
        let topLeading: RowSlot = folder ? .folderPath : (branch ? .gitBranch : .none)
        return [
            .topLeading: topLeading,
            .topTrailing: RowSlotPosition.topTrailing.defaultSlot,
            .bottomLeading: folder && branch ? .gitBranch : .none,
            .bottomTrailing: RowSlotPosition.bottomTrailing.defaultSlot
        ]
    }

    static func pendingValues(stored: (String) -> Any?) -> [String: String] {
        guard RowSlotPosition.allCases.allSatisfy({ stored($0.storageKey) == nil }) else { return [:] }
        let migrated = slots(
            showFolderPath: stored(AppStorageKeys.monitorShowFolderPath) as? Bool,
            showBranch: stored(AppStorageKeys.monitorShowBranch) as? Bool
        )
        return Dictionary(uniqueKeysWithValues: migrated.map { ($0.key.storageKey, $0.value.rawValue) })
    }
}

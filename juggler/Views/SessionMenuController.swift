import AppKit
import Carbon.HIToolbox
import Observation

@MainActor
@Observable
final class SessionMenuController {
    enum Mode: Equatable {
        case menu
        case rename
        case note
    }

    enum KeyDisposition: Equatable {
        case close
        case back
        case swallow
        case passThrough
    }

    static let actions: [SessionRowAction] = [.prio, .hide, .rename, .note]

    let target: Session
    let sessionName: String
    private(set) var mode: Mode = .menu
    private(set) var isClosed = false
    private let sessionManager: SessionManager
    private let queueOrderMode: () -> QueueOrderMode
    private let showBeacon: (String) -> Void
    private let onClose: (SessionMenuController) -> Void

    init(
        target: Session,
        sessionName: String,
        sessionManager: SessionManager,
        queueOrderMode: @escaping () -> QueueOrderMode,
        showBeacon: @escaping (String) -> Void,
        onClose: @escaping (SessionMenuController) -> Void
    ) {
        self.target = target
        self.sessionName = sessionName
        self.sessionManager = sessionManager
        self.queueOrderMode = queueOrderMode
        self.showBeacon = showBeacon
        self.onClose = onClose
    }

    static func isSameConversation(_ session: Session, as target: Session) -> Bool {
        guard let key = target.noteKey else { return session.id == target.id }
        return session.noteKey == key
    }

    var session: Session? {
        sessionManager.sessions.first { $0.id == target.id && Self.isSameConversation($0, as: target) }
    }

    var acceptsShortcuts: Bool {
        !isClosed && mode == .menu
    }

    func isAvailable(_ action: SessionRowAction) -> Bool {
        action.isAvailable(in: queueOrderMode())
    }

    func perform(_ action: SessionRowAction) {
        guard acceptsShortcuts, isAvailable(action) else { return }
        guard let session else { return closeAsUnavailable() }
        switch action {
        case .prio:
            sessionManager.toggleSessionPrioritized(sessionID: session.id)
            close()
        case .hide:
            sessionManager.toggleSessionHidden(sessionID: session.id)
            close()
        case .rename:
            mode = .rename
        case .note:
            mode = .note
        }
    }

    func perform(_ shortcut: RowActionShortcut) {
        guard let action = SessionRowAction(shortcut) else { return }
        perform(action)
    }

    func save(_ draft: String) {
        guard !isClosed else { return }
        switch mode {
        case .menu:
            return
        case .rename:
            guard let session else { return closeAsUnavailable() }
            sessionManager.renameSession(terminalSessionID: session.id, customName: draft)
            close()
        case .note:
            guard sessionManager.updateNote(for: target, note: draft) else { return closeAsUnavailable() }
            close()
        }
    }

    func clearName() {
        guard !isClosed, mode == .rename else { return }
        guard let session else { return closeAsUnavailable() }
        sessionManager.renameSession(terminalSessionID: session.id, customName: nil)
        close()
    }

    func keyDisposition(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isRepeat: Bool,
        hasMarkedText: Bool
    ) -> KeyDisposition {
        if hasMarkedText { return .passThrough }
        let modifiers = modifiers.intersection([.command, .option, .control, .shift])
        if modifiers == .control, keyCode == UInt16(kVK_ANSI_C) { return .close }
        if modifiers.isEmpty, keyCode == UInt16(kVK_Escape) {
            if isRepeat { return .swallow }
            return mode == .menu ? .close : .back
        }
        return mode == .menu ? .swallow : .passThrough
    }

    func apply(_ disposition: KeyDisposition) {
        switch disposition {
        case .close: close()
        case .back: mode = .menu
        case .swallow, .passThrough: break
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        onClose(self)
    }

    private func closeAsUnavailable() {
        close()
        showBeacon("Session No Longer Available")
    }
}

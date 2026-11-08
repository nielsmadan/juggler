import AppKit
import SwiftUI

struct SessionNoteEditorPresentation {
    let sessionName: String
    let note: String?
    let onSave: (String) -> Void
    let onCancel: () -> Void
}

@MainActor
final class SessionNoteEditorManager: NSObject, NSWindowDelegate {
    typealias PresentationHandler = @MainActor (SessionNoteEditorPresentation) -> Void

    static let shared = SessionNoteEditorManager()

    private var panel: NSPanel?
    private var target: Session?
    private var previousApp: NSRunningApplication?
    private let presentationHandler: PresentationHandler?

    init(presentationHandler: PresentationHandler? = nil) {
        self.presentationHandler = presentationHandler
        super.init()
    }

    func editFocusedSession(
        in sessionManager: SessionManager = .shared,
        showBeacon: @MainActor (String, Bool) -> Void = { title, force in
            BeaconManager.shared.show(sessionName: title, force: force)
        }
    ) {
        let focusedSession = sessionManager.focusedTrackedSession
        if isPresenting, let focusedSession, !isEditing(focusedSession) {
            present(session: focusedSession, sessionManager: sessionManager)
            return
        }
        if isPresenting {
            if focusedSession != nil {
                previousApp = NSWorkspace.shared.frontmostApplication
            }
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        guard let focusedSession else {
            showBeacon("No Active Session", true)
            return
        }
        present(session: focusedSession, sessionManager: sessionManager)
    }

    private var isPresenting: Bool {
        panel?.isVisible == true || presentationHandler != nil && target != nil
    }

    private func isEditing(_ session: Session) -> Bool {
        guard let target else { return false }
        if let targetKey = target.noteKey, let sessionKey = session.noteKey {
            return targetKey == sessionKey
        }
        return target.id == session.id
            && target.agentSessionIdentity == session.agentSessionIdentity
            && target.startedAt == session.startedAt
    }

    private func present(session: Session, sessionManager: SessionManager) {
        previousApp = NSWorkspace.shared.frontmostApplication
        target = session
        let titleMode = SessionTitleMode(
            rawValue: UserDefaults.standard.string(forKey: AppStorageKeys.sessionTitleMode) ?? ""
        ) ?? .default
        let sessionName = sessionManager.disambiguatedDisplayName(for: session, titleMode: titleMode)
        let presentation = SessionNoteEditorPresentation(
            sessionName: sessionName,
            note: session.note,
            onSave: { [weak self] in self?.save($0, target: session, sessionManager: sessionManager) },
            onCancel: { [weak self] in self?.close() }
        )
        if let presentationHandler {
            presentationHandler(presentation)
            return
        }

        let content = SessionNoteEditorView(
            sessionName: presentation.sessionName,
            note: presentation.note,
            onSave: presentation.onSave,
            onCancel: presentation.onCancel
        )

        let hosting = NSHostingController(rootView: content)
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered,
                defer: true
            )
            panel.title = "Session Note"
            panel.titleVisibility = .hidden
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.delegate = self
            self.panel = panel
        }
        panel?.contentViewController = hosting

        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func save(_ note: String, target: Session, sessionManager: SessionManager) {
        let saved = sessionManager.updateNote(for: target, note: note)
        close()
        if !saved {
            BeaconManager.shared.show(sessionName: "Session No Longer Available", force: true)
        }
    }

    private func close() {
        if panel?.isVisible == true {
            panel?.close()
        } else {
            finishEditing()
        }
    }

    func windowWillClose(_: Notification) {
        finishEditing()
    }

    private func finishEditing() {
        target = nil
        previousApp?.activate()
        previousApp = nil
    }
}

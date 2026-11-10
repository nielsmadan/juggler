import AppKit
import SwiftUI

final class SessionMenuPanel: NSPanel {
    var keyHandler: ((NSEvent, Bool) -> Bool)?

    override var canBecomeKey: Bool { true }

    private var hasMarkedText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event, hasMarkedText) == true { return }
        super.sendEvent(event)
    }

    /// Consumes every Command shortcut so ⌘Q and friends never reach Juggler's main menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event, hasMarkedText) == true { return true }
        guard event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        if let action = Self.textEditingAction(
            characters: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags
        ) {
            NSApp.sendAction(action, to: nil, from: self)
        }
        return true
    }

    static func textEditingAction(characters: String?, modifiers: NSEvent.ModifierFlags) -> Selector? {
        let modifiers = modifiers.intersection([.command, .option, .control, .shift])
        switch (characters?.lowercased(), modifiers) {
        case ("x", .command): return #selector(NSText.cut(_:))
        case ("c", .command): return #selector(NSText.copy(_:))
        case ("v", .command): return #selector(NSText.paste(_:))
        case ("a", .command): return #selector(NSText.selectAll(_:))
        case ("z", .command): return Selector(("undo:"))
        case ("z", [.command, .shift]): return Selector(("redo:"))
        default: return nil
        }
    }
}

@MainActor
final class SessionMenuManager: NSObject, NSWindowDelegate {
    typealias PresentationHandler = @MainActor (SessionMenuController) -> Void

    static let shared = SessionMenuManager()

    private(set) var controller: SessionMenuController?
    private var panel: SessionMenuPanel?
    private var anchorFrame: NSRect = .zero
    private let sessionManager: SessionManager
    private let queueOrderMode: () -> QueueOrderMode
    private let titleMode: () -> SessionTitleMode
    private let showBeacon: (String) -> Void
    private let presentationHandler: PresentationHandler?

    init(
        sessionManager: SessionManager = .shared,
        queueOrderMode: @escaping () -> QueueOrderMode = { .stored() },
        titleMode: @escaping () -> SessionTitleMode = { .stored() },
        showBeacon: @escaping (String) -> Void = { BeaconManager.shared.show(sessionName: $0, force: true) },
        presentationHandler: PresentationHandler? = nil
    ) {
        self.sessionManager = sessionManager
        self.queueOrderMode = queueOrderMode
        self.titleMode = titleMode
        self.showBeacon = showBeacon
        self.presentationHandler = presentationHandler
        super.init()
    }

    /// Opens the menu for the focused session, closes it on a repeat press, and retargets it
    /// when focus has moved to another conversation.
    func toggleForFocusedSession() {
        let focusedSession = sessionManager.focusedTrackedSession
        if let controller,
           focusedSession.map({ SessionMenuController.isSameConversation($0, as: controller.target) }) ?? true {
            return close()
        }
        guard let focusedSession else {
            logDebug(.hotkey, "Session menu: no focused tracked session")
            return showBeacon("No Active Session")
        }
        present(focusedSession)
    }

    func close() {
        controller?.close()
    }

    func windowDidResignKey(_: Notification) {
        close()
    }

    private func present(_ session: Session) {
        controller?.close()
        let controller = SessionMenuController(
            target: session,
            sessionName: sessionManager.disambiguatedDisplayName(for: session, titleMode: titleMode()),
            sessionManager: sessionManager,
            queueOrderMode: queueOrderMode,
            showBeacon: showBeacon,
            onClose: { [weak self] in self?.controllerDidClose($0) }
        )
        self.controller = controller
        if let presentationHandler {
            presentationHandler(controller)
            return
        }
        showPanel(for: controller)
    }

    private func controllerDidClose(_ closed: SessionMenuController) {
        guard controller === closed else { return }
        controller = nil
        hidePanel()
    }

    private func showPanel(for controller: SessionMenuController) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.keyHandler = { [weak controller] event, hasMarkedText in
            guard let controller else { return false }
            let disposition = controller.keyDisposition(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                isRepeat: event.isARepeat,
                hasMarkedText: hasMarkedText
            )
            controller.apply(disposition)
            return disposition != .passThrough
        }
        let hosting = NSHostingController(rootView: SessionMenuView(controller: controller) { [weak self] size in
            self?.layoutPanel(size: size)
        })
        hosting.sizingOptions = []
        panel.contentViewController = hosting
        anchorFrame = FrontmostWindow.frame() ?? NSScreen.main?.visibleFrame ?? .zero
        layoutPanel(size: hosting.view.fittingSize)
        panel.makeKeyAndOrderFront(nil)
    }

    private func layoutPanel(size: CGSize) {
        let origin = BeaconPositionCalculator.calculateOrigin(
            position: .center,
            referenceFrame: anchorFrame,
            panelSize: size
        )
        panel?.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Content teardown waits a tick: closing runs inside the button, field or shortcut
    /// callback whose view would otherwise be freed mid-call.
    private func hidePanel() {
        guard let panel else { return }
        panel.orderOut(nil)
        let content = panel.contentViewController
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.contentViewController === content else { return }
            panel.contentViewController = nil
        }
    }

    private func makePanel() -> SessionMenuPanel {
        let panel = SessionMenuPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.applyFloatingOverlayStyle()
        panel.title = "Session Menu"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self
        return panel
    }
}

extension NSPanel {
    func applyFloatingOverlayStyle() {
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

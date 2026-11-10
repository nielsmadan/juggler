import AppKit
import Carbon.HIToolbox
@testable import Juggler
import ShortcutKit
import Testing

@Suite("SessionMenuManager", .serialized)
@MainActor
struct SessionMenuManagerTests {
    private let escape = UInt16(kVK_Escape)
    private let keyC = UInt16(kVK_ANSI_C)
    private let keyX = UInt16(kVK_ANSI_X)

    private func session(_ id: String, conversation: String = "") -> Session {
        Session(
            agentSessionID: conversation,
            terminalSessionID: id,
            terminalType: .iterm2,
            agent: "codex",
            projectPath: "/test/\(id)",
            state: .idle,
            startedAt: Date()
        )
    }

    private func focusedManager(
        _ sessions: [Session],
        focused: String,
        noteStore: SessionNoteStore? = nil
    ) -> SessionManager {
        let sessionManager = TestFixtures.isolatedSessionManager(noteStore: noteStore)
        sessionManager.testSetSessions(sessions)
        sessionManager.isTerminalAppActive = true
        sessionManager.testSetFocusedSessionID(focused)
        sessionManager.frontmostTerminalTypeProvider = { .iterm2 }
        return sessionManager
    }

    private func menu(
        _ sessionManager: SessionManager,
        mode: QueueOrderMode = .fair,
        beacons: @escaping (String) -> Void = { _ in },
        presented: @escaping (SessionMenuController) -> Void = { _ in }
    ) -> SessionMenuManager {
        SessionMenuManager(
            sessionManager: sessionManager,
            queueOrderMode: { mode },
            titleMode: { .default },
            showBeacon: beacons,
            presentationHandler: presented
        )
    }

    private func openController(_ menu: SessionMenuManager) throws -> SessionMenuController {
        menu.toggleForFocusedSession()
        return try #require(menu.controller)
    }

    @Test func noFocusedTrackedSessionShowsNoActiveSessionBeacon() {
        let sessionManager = focusedManager([session("available")], focused: "unknown")
        var beacons: [String] = []
        let menu = menu(sessionManager, beacons: { beacons.append($0) })

        menu.toggleForFocusedSession()

        #expect(beacons == ["No Active Session"])
        #expect(menu.controller == nil)
    }

    @Test func opensForTheFocusedSession() throws {
        let sessionManager = focusedManager([session("first"), session("focused")], focused: "focused")
        var presented: [String] = []
        let menu = menu(sessionManager, presented: { presented.append($0.target.id) })

        let controller = try openController(menu)

        #expect(presented == ["focused"])
        #expect(controller.mode == .menu)
    }

    @Test func prioTogglesOnceAndCloses() throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        let menu = menu(sessionManager)
        let controller = try openController(menu)

        controller.perform(.prio)
        controller.perform(.prio)

        #expect(sessionManager.sessions[0].isPrioritized)
        #expect(controller.isClosed)
        #expect(menu.controller == nil)
    }

    @Test func hideTogglesOnceAndCloses() throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        let menu = menu(sessionManager)
        let controller = try openController(menu)

        controller.perform(.hide)
        controller.perform(.hide)

        #expect(sessionManager.sessions[0].isHidden)
        #expect(menu.controller == nil)
    }

    @Test(arguments: [
        (RowActionShortcut.monitor(.toggleSelectedPrioritized), SessionRowAction.prio),
        (.monitor(.toggleSelectedHidden), .hide),
        (.list(.rename), .rename),
        (.list(.editNote), .note)
    ])
    func monitorShortcutsDriveTheMatchingAction(shortcut: RowActionShortcut, action: SessionRowAction) throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        let controller = try openController(menu(sessionManager))

        controller.perform(shortcut)

        switch action {
        case .prio: #expect(sessionManager.sessions[0].isPrioritized)
        case .hide: #expect(sessionManager.sessions[0].isHidden)
        case .rename: #expect(controller.mode == .rename)
        case .note: #expect(controller.mode == .note)
        }
    }

    @Test(arguments: [
        RowActionShortcut.list(.backburner), .list(.sendToBack), .list(.activate), .monitor(.toggleHiddenVisibility)
    ])
    func unmappedShortcutsLeaveTheSessionAndMenuAlone(shortcut: RowActionShortcut) throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        let menu = menu(sessionManager)
        let controller = try openController(menu)

        controller.perform(shortcut)

        #expect(sessionManager.sessions[0].state == .idle)
        #expect(!sessionManager.showsHiddenSessions)
        #expect(menu.controller === controller)
        #expect(controller.mode == .menu)
    }

    @Test(arguments: [QueueOrderMode.prio, .static, .grouped])
    func prioOutsideFairModeNeitherTogglesNorCloses(mode: QueueOrderMode) throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        let menu = menu(sessionManager, mode: mode)
        let controller = try openController(menu)

        controller.perform(.prio)

        #expect(!controller.isAvailable(.prio))
        #expect(!sessionManager.sessions[0].isPrioritized)
        #expect(menu.controller === controller)
    }

    @Test func storedQueueOrderModeFallsBackToFair() {
        let defaults = TestDefaults.fresh()
        #expect(QueueOrderMode.stored(in: defaults) == .fair)
        defaults.set(QueueOrderMode.grouped.rawValue, forKey: AppStorageKeys.queueOrderMode)
        #expect(QueueOrderMode.stored(in: defaults) == .grouped)
    }

    @Test func renameSavesAndCloses() throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        let menu = menu(sessionManager)
        let controller = try openController(menu)

        controller.perform(.rename)
        controller.save("Parser work")

        #expect(sessionManager.sessions[0].customName == "Parser work")
        #expect(menu.controller == nil)
    }

    @Test func clearRemovesTheCustomName() throws {
        var renamed = session("focused")
        renamed.customName = "Old name"
        let sessionManager = focusedManager([renamed], focused: "focused")
        let controller = try openController(menu(sessionManager))

        controller.perform(.rename)
        controller.clearName()

        #expect(sessionManager.sessions[0].customName == nil)
    }

    @Test func noteSavesAndCloses() throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        let menu = menu(sessionManager)
        let controller = try openController(menu)

        controller.perform(.note)
        controller.save("Finish parser")

        #expect(sessionManager.sessions[0].note == "Finish parser")
        #expect(menu.controller == nil)
    }

    @Test func noteStaysWithTheConversationWhenAnotherTakesOverThePane() throws {
        let notes = SessionNoteStore(defaults: TestDefaults.fresh("notes"))
        let sessionManager = focusedManager([session("pane", conversation: "first")], focused: "pane",
                                            noteStore: notes)
        let controller = try openController(menu(sessionManager))

        controller.perform(.note)
        sessionManager.testSetSessions([session("pane", conversation: "second")])
        controller.save("For the first conversation")

        #expect(sessionManager.sessions[0].note == nil)
        #expect(notes.note(for: .init(agent: "codex", agentSessionID: "first")) == "For the first conversation")
    }

    @Test func togglesSkipAConversationThatTookOverThePane() throws {
        var beacons: [String] = []
        let sessionManager = focusedManager([session("pane", conversation: "first")], focused: "pane")
        let controller = try openController(menu(sessionManager, beacons: { beacons.append($0) }))

        sessionManager.testSetSessions([session("pane", conversation: "second")])
        controller.perform(.prio)

        #expect(!sessionManager.sessions[0].isPrioritized)
        #expect(beacons == ["Session No Longer Available"])
    }

    @Test func escapeStepsBackFromTheEditorThenCloses() throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        let menu = menu(sessionManager)
        let controller = try openController(menu)
        controller.perform(.note)

        controller.apply(controller.keyDisposition(keyCode: escape, modifiers: [], isRepeat: false,
                                                   hasMarkedText: false))
        #expect(controller.mode == .menu)
        controller.apply(controller.keyDisposition(keyCode: escape, modifiers: [], isRepeat: false,
                                                   hasMarkedText: false))
        #expect(menu.controller == nil)
    }

    @Test func heldEscapeDoesNotCloseAfterSteppingBack() throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        let controller = try openController(menu(sessionManager))

        #expect(controller.keyDisposition(keyCode: escape, modifiers: [], isRepeat: true, hasMarkedText: false)
            == .swallow)
    }

    @Test(arguments: [NSEvent.ModifierFlags.control, [.control, .capsLock]])
    func controlCClosesFromTheEditor(modifiers: NSEvent.ModifierFlags) throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        let controller = try openController(menu(sessionManager))
        controller.perform(.rename)

        #expect(controller.keyDisposition(keyCode: keyC, modifiers: modifiers, isRepeat: false,
                                          hasMarkedText: false) == .close)
    }

    @Test func composingTextKeepsEscapeAndControlCInTheField() throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        let controller = try openController(menu(sessionManager))
        controller.perform(.note)

        #expect(controller.keyDisposition(keyCode: escape, modifiers: [], isRepeat: false, hasMarkedText: true)
            == .passThrough)
        #expect(controller.keyDisposition(keyCode: keyC, modifiers: .control, isRepeat: false, hasMarkedText: true)
            == .passThrough)
    }

    @Test func menuSwallowsUnboundKeys() throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        let controller = try openController(menu(sessionManager))

        #expect(controller.keyDisposition(keyCode: keyX, modifiers: [], isRepeat: false, hasMarkedText: false)
            == .swallow)
    }

    @Test func editorPassesTypingAndCommandKeysToTheField() throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        let controller = try openController(menu(sessionManager))
        controller.perform(.note)

        #expect(controller.keyDisposition(keyCode: keyX, modifiers: [], isRepeat: false, hasMarkedText: false)
            == .passThrough)
        #expect(controller.keyDisposition(keyCode: keyC, modifiers: .command, isRepeat: false, hasMarkedText: false)
            == .passThrough)
    }

    @Test func commandShortcutsMapToTextEditingActions() {
        #expect(SessionMenuPanel.textEditingAction(characters: "v", modifiers: .command)
            == #selector(NSText.paste(_:)))
        #expect(SessionMenuPanel.textEditingAction(characters: "z", modifiers: [.command, .shift])
            == Selector(("redo:")))
        #expect(SessionMenuPanel.textEditingAction(characters: "q", modifiers: .command) == nil)
    }

    @Test func pressingTheShortcutAgainClosesTheMenu() throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        var presented = 0
        let menu = menu(sessionManager, presented: { _ in presented += 1 })

        menu.toggleForFocusedSession()
        menu.toggleForFocusedSession()

        #expect(presented == 1)
        #expect(menu.controller == nil)
    }

    @Test func reopensAfterClosing() throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        var presented = 0
        let menu = menu(sessionManager, presented: { _ in presented += 1 })

        try openController(menu).close()
        menu.toggleForFocusedSession()

        #expect(presented == 2)
        #expect(menu.controller?.target.id == "focused")
    }

    @Test func pressingTheShortcutFromAnotherFocusedSessionRetargets() throws {
        let sessionManager = focusedManager([session("first"), session("second")], focused: "first")
        var presented: [String] = []
        let menu = menu(sessionManager, presented: { presented.append($0.target.id) })

        let first = try openController(menu)
        sessionManager.testSetFocusedSessionID("second")
        let second = try openController(menu)
        second.perform(.note)
        second.save("Second task")

        #expect(presented == ["first", "second"])
        #expect(first.isClosed)
        #expect(sessionManager.sessions.map(\.note) == [nil, "Second task"])
    }

    @Test func closingAStaleControllerLeavesTheCurrentMenuOpen() throws {
        let sessionManager = focusedManager([session("first"), session("second")], focused: "first")
        let menu = menu(sessionManager)

        let first = try openController(menu)
        sessionManager.testSetFocusedSessionID("second")
        let second = try openController(menu)
        first.close()

        #expect(menu.controller === second)
    }

    @Test func actingOnASessionThatHasGoneShowsABeacon() throws {
        let sessionManager = focusedManager([session("focused")], focused: "focused")
        var beacons: [String] = []
        let menu = menu(sessionManager, beacons: { beacons.append($0) })
        let controller = try openController(menu)

        sessionManager.testSetSessions([])
        controller.perform(.hide)

        #expect(beacons == ["Session No Longer Available"])
        #expect(menu.controller == nil)
    }

    @Test func infoLinesListTheSessionDetailsWithoutRepeatingTheFolder() {
        var detailed = session("focused")
        detailed.gitBranch = "main"
        detailed.details.model = "opus"

        let lines = SessionMenuInfoLine.lines(for: detailed, now: Date(), abbreviateHome: false)

        #expect(lines.map(\.slot) == [.folderPath, .gitBranch, .model])
        #expect(lines.map(\.text) == ["/test/focused", "main", "opus"])
    }

    @Test func shortcutHintsFollowTheMonitorBindings() {
        let list = ShortcutContext<SessionListAction>("hudTestList")
        let monitor = ShortcutContext<SessionMonitorAction>("hudTestMonitor")
        let registry = ShortcutRegistry(contexts: [list, monitor], store: MemoryShortcutStore())

        list.setShortcuts([Shortcut("n")], for: .editNote)
        monitor.setShortcuts([Shortcut("u")], for: .toggleSelectedPrioritized)

        #expect(SessionRowAction.allCases.map { $0.shortcutDisplayString(list: list, monitor: monitor) } == [
            Shortcut("r").displayString,
            Shortcut("n").displayString,
            Shortcut("e").displayString,
            Shortcut("u").displayString
        ])
        withExtendedLifetime(registry) {}
    }
}

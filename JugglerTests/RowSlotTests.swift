import AppKit
import Foundation
@testable import Juggler
import Testing

private let now = Date(timeIntervalSince1970: 1_000_000)

private func populatedSession(projectPath: String = "/work/org/app") -> Session {
    var session = Session(
        agentSessionID: "native",
        terminalSessionID: "w0t0p0:abc",
        terminalType: .iterm2,
        agent: "codex",
        projectPath: projectPath,
        terminalTabName: "tab",
        terminalWindowName: "window",
        customName: "Renamed",
        state: .working,
        startedAt: now
    )
    session.gitBranch = "main"
    session.details = SessionDetails(
        agentTitle: "Fix the parser",
        model: "gpt-5.5-codex",
        effort: "high",
        permissionMode: "acceptEdits",
        currentTool: "Bash",
        lastProblem: "rate_limit_error",
        subagentCount: 2,
        contextPercent: 41,
        processStartedAt: now.addingTimeInterval(-3720),
        observedAt: now
    )
    session.turnCount = 3
    return session
}

private func slotMap(
    _ topLeading: RowSlot,
    _ topTrailing: RowSlot,
    _ bottomLeading: RowSlot,
    _ bottomTrailing: RowSlot
) -> [RowSlotPosition: RowSlot] {
    [
        .topLeading: topLeading,
        .topTrailing: topTrailing,
        .bottomLeading: bottomLeading,
        .bottomTrailing: bottomTrailing
    ]
}

@Suite("RowSlot")
struct RowSlotTests {
    @Test func everySlot_populatedSession() {
        let expected: [RowSlot: String] = [
            .folderPath: "/work/org/app",
            .folderName: "app",
            .parentAndFolderName: "org/app",
            .tabTitle: "tab",
            .windowTitle: "window",
            .agentTitle: "Fix the parser",
            .gitBranch: "main",
            .model: "gpt-5.5-codex",
            .effort: "high",
            .permissionMode: "Accept Edits",
            .currentTool: "Bash",
            .lastProblem: "Rate limited",
            .subagents: "2 subagents",
            .contextPercent: "41% context",
            .turns: "3 turns",
            .runTime: "1h02m"
        ]
        #expect(expected.count == RowSlot.allCases.count - 1)
        let session = populatedSession()
        for slot in RowSlot.allCases {
            #expect(slot.value(for: session, now: now, abbreviateHome: false) == expected[slot], "\(slot)")
        }
    }

    @Test func everySlot_emptySession() {
        let expected: [RowSlot: String] = [
            .folderPath: "/test/s1",
            .folderName: "s1",
            .parentAndFolderName: "test/s1"
        ]
        let session = makeSession("s1")
        for slot in RowSlot.allCases {
            #expect(slot.value(for: session, now: now, abbreviateHome: false) == expected[slot], "\(slot)")
        }
    }

    @Test func singularCounts() {
        var session = makeSession("s1")
        session.details.subagentCount = 1
        session.turnCount = 1
        session.details.contextPercent = 0
        #expect(RowSlot.subagents.value(for: session, now: now, abbreviateHome: false) == "1 subagent")
        #expect(RowSlot.turns.value(for: session, now: now, abbreviateHome: false) == "1 turn")
        #expect(RowSlot.contextPercent.value(for: session, now: now, abbreviateHome: false) == "0% context")
    }

    @Test func turns_preferHooklinesinkerCountOverJugglers() {
        var session = makeSession("s1")
        session.turnCount = 3
        #expect(RowSlot.turns.value(for: session, now: now, abbreviateHome: false) == "3 turns")
        session.details.turns = 5
        #expect(RowSlot.turns.value(for: session, now: now, abbreviateHome: false) == "5 turns")
        session.details.turns = 0
        #expect(RowSlot.turns.value(for: session, now: now, abbreviateHome: false) == nil)
    }

    @Test func folderPath_abbreviatesHomeOnlyWhenAsked() {
        let session = populatedSession(projectPath: NSHomeDirectory() + "/code/app")
        #expect(RowSlot.folderPath.value(for: session, now: now, abbreviateHome: true) == "~/code/app")
        #expect(
            RowSlot.folderPath.value(for: session, now: now, abbreviateHome: false)
                == NSHomeDirectory() + "/code/app"
        )
    }

    @Test func folderSlots_ignoreCustomName() {
        let session = populatedSession()
        #expect(session.customName == "Renamed")
        #expect(RowSlot.folderName.value(for: session, now: now, abbreviateHome: false) == "app")
        #expect(RowSlot.parentAndFolderName.value(for: session, now: now, abbreviateHome: false) == "org/app")
    }

    @Test func tabTitle_missingOrEmpty_isNil() {
        var session = makeSession("s1")
        #expect(RowSlot.tabTitle.value(for: session, now: now, abbreviateHome: false) == nil)
        session.terminalTabName = ""
        #expect(RowSlot.tabTitle.value(for: session, now: now, abbreviateHome: false) == nil)
    }

    @Test func everySlot_hasNameAndSymbol() {
        for slot in RowSlot.allCases {
            #expect(!slot.displayName.isEmpty)
            #expect(
                NSImage(systemSymbolName: slot.systemImage, accessibilityDescription: nil) != nil,
                "\(slot.systemImage)"
            )
        }
        #expect(Set(RowSlot.allCases.map(\.displayName)).count == RowSlot.allCases.count)
        #expect(RowSlot.allCases.count == 17)
    }

    @Test func permissionModeLabels() {
        let expected = [
            "default": "Default",
            "plan": "Plan",
            "acceptEdits": "Accept Edits",
            "bypassPermissions": "Bypass",
            "auto": "Auto",
            "dontAsk": "Don't Ask",
            "auto-high": "Auto High",
            "read_only": "Read Only",
            "yolo": "Yolo"
        ]
        for (mode, label) in expected {
            #expect(RowSlotLabels.permissionMode(mode) == label)
        }
    }

    @Test func problemLabels() {
        let expected = [
            "rate_limit": "Rate limited",
            "rate_limit_error": "Rate limited",
            "overloaded": "Overloaded",
            "overloaded_error": "Overloaded",
            "billing_error": "Billing error",
            "authentication_failed": "Auth failed",
            "max_output_tokens": "Output limit",
            "max_steps_exceeded": "Step limit",
            "interrupted": "Interrupted",
            "error": "Error",
            "context_window_exceeded": "Context window exceeded",
            "refusal": "Refusal"
        ]
        for (token, label) in expected {
            #expect(RowSlotLabels.problem(token) == label)
        }
    }

    @Test func positions_defaultsAndKeys() {
        #expect(RowSlotPosition.topLeading.defaultSlot == .folderPath)
        #expect(RowSlotPosition.topTrailing.defaultSlot == .model)
        #expect(RowSlotPosition.bottomLeading.defaultSlot == .gitBranch)
        #expect(RowSlotPosition.bottomTrailing.defaultSlot == .effort)
        let defaults = RowSlotPosition.registrationDefaults
        #expect(defaults["monitorSlotTopLeading"] as? String == "folderPath")
        #expect(defaults["monitorSlotTopTrailing"] as? String == "model")
        #expect(defaults["monitorSlotBottomLeading"] as? String == "gitBranch")
        #expect(defaults["monitorSlotBottomTrailing"] as? String == "effort")
    }
}

@Suite("ResolvedSlotGrid")
struct ResolvedSlotGridTests {
    @Test func defaultSlots_renderBothRows() {
        let grid = ResolvedSlotGrid.resolve(
            slotMap(.folderPath, .model, .gitBranch, .effort),
            session: populatedSession(),
            now: now,
            abbreviateHome: false
        )
        #expect(grid == ResolvedSlotGrid(
            top: ResolvedSlotRow(
                leading: ResolvedSlot(slot: .folderPath, text: "/work/org/app"),
                trailing: ResolvedSlot(slot: .model, text: "gpt-5.5-codex")
            ),
            bottom: ResolvedSlotRow(
                leading: ResolvedSlot(slot: .gitBranch, text: "main"),
                trailing: ResolvedSlot(slot: .effort, text: "high")
            )
        ))
    }

    @Test func rowWithBothNone_isHidden() {
        let grid = ResolvedSlotGrid.resolve(
            slotMap(.none, .none, .gitBranch, .none),
            session: populatedSession(),
            now: now,
            abbreviateHome: false
        )
        #expect(grid == ResolvedSlotGrid(
            top: nil,
            bottom: ResolvedSlotRow(leading: ResolvedSlot(slot: .gitBranch, text: "main"), trailing: nil)
        ))
    }

    @Test func allNone_hasNoRows() {
        let grid = ResolvedSlotGrid.resolve(
            slotMap(.none, .none, .none, .none),
            session: populatedSession(),
            now: now,
            abbreviateHome: false
        )
        #expect(grid == ResolvedSlotGrid(top: nil, bottom: nil))
    }

    @Test func missingValues_keepTheirRow() {
        let grid = ResolvedSlotGrid.resolve(
            slotMap(.model, .none, .gitBranch, .effort),
            session: makeSession("s1"),
            now: now,
            abbreviateHome: false
        )
        #expect(grid == ResolvedSlotGrid(
            top: ResolvedSlotRow(leading: ResolvedSlot(slot: .model, text: nil), trailing: nil),
            bottom: ResolvedSlotRow(
                leading: ResolvedSlot(slot: .gitBranch, text: nil),
                trailing: ResolvedSlot(slot: .effort, text: nil)
            )
        ))
    }

    @Test func folderPath_honoursAbbreviateHome() {
        let grid = ResolvedSlotGrid.resolve(
            slotMap(.folderPath, .none, .none, .none),
            session: populatedSession(projectPath: NSHomeDirectory() + "/code/app"),
            now: now,
            abbreviateHome: true
        )
        #expect(grid.top?.leading == ResolvedSlot(slot: .folderPath, text: "~/code/app"))
    }
}

@Suite("RowSlotMigration")
struct RowSlotMigrationTests {
    @Test func slotTable() {
        #expect(RowSlotMigration.slots(showFolderPath: true, showBranch: true)
            == slotMap(.folderPath, .model, .gitBranch, .effort))
        #expect(RowSlotMigration.slots(showFolderPath: true, showBranch: false)
            == slotMap(.folderPath, .model, .none, .effort))
        #expect(RowSlotMigration.slots(showFolderPath: false, showBranch: true)
            == slotMap(.gitBranch, .model, .none, .effort))
        #expect(RowSlotMigration.slots(showFolderPath: false, showBranch: false)
            == slotMap(.none, .model, .none, .effort))
    }

    @Test func neverSetKeys_countAsShown() {
        #expect(RowSlotMigration.slots(showFolderPath: nil, showBranch: nil)
            == slotMap(.folderPath, .model, .gitBranch, .effort))
        #expect(RowSlotMigration.slots(showFolderPath: nil, showBranch: false)
            == slotMap(.folderPath, .model, .none, .effort))
        #expect(RowSlotMigration.slots(showFolderPath: false, showBranch: nil)
            == slotMap(.gitBranch, .model, .none, .effort))
    }

    @Test func pendingValues_freshInstallWritesDefaults() {
        let values = RowSlotMigration.pendingValues(stored: { _ in nil })
        #expect(values == [
            "monitorSlotTopLeading": "folderPath",
            "monitorSlotTopTrailing": "model",
            "monitorSlotBottomLeading": "gitBranch",
            "monitorSlotBottomTrailing": "effort"
        ])
    }

    @Test func pendingValues_readsOldToggles() {
        let stored: [String: Any] = ["monitorShowFolderPath": false, "monitorShowBranch": true]
        let values = RowSlotMigration.pendingValues(stored: { stored[$0] })
        #expect(values == [
            "monitorSlotTopLeading": "gitBranch",
            "monitorSlotTopTrailing": "model",
            "monitorSlotBottomLeading": "none",
            "monitorSlotBottomTrailing": "effort"
        ])
    }

    @Test func pendingValues_alreadyMigrated_writesNothing() {
        let stored: [String: Any] = ["monitorSlotBottomTrailing": "turns", "monitorShowFolderPath": false]
        #expect(RowSlotMigration.pendingValues(stored: { stored[$0] }).isEmpty)
    }
}

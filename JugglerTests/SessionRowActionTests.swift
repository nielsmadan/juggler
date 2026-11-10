import CoreGraphics
import Foundation
@testable import Juggler
import SwiftUI
import Testing

@MainActor
struct SessionRowActionTests {
    @Test(arguments: 0 ..< 8)
    func legacyVisibilityTogglesMigrateIntoSlots(mask: Int) {
        let legacy: [String: Any] = [
            "monitorShowRenameButton": mask & 1 != 0,
            "monitorShowNoteButton": mask & 2 != 0,
            "monitorShowHideButton": mask & 4 != 0
        ]
        let values = RowActionMigration.pendingValues(stored: { legacy[$0] })
        let expected: [String?] = [
            mask & 1 != 0 ? "rename" : "none",
            mask & 2 != 0 ? "note" : "none",
            mask & 4 != 0 ? "hide" : "none"
        ]
        #expect(["monitorRowActionFirst", "monitorRowActionSecond", "monitorRowActionThird"].map { values[$0] }
            == expected)
    }

    @Test func freshInstallMigratesToTheDefaultActions() {
        let values = RowActionMigration.pendingValues(stored: { _ in nil })
        #expect(values == [
            "monitorRowActionFirst": "rename", "monitorRowActionSecond": "note", "monitorRowActionThird": "hide"
        ])
    }

    @Test func anyWrittenSlotSkipsTheMigration() {
        let stored: [String: Any] = ["monitorShowRenameButton": false, "monitorRowActionThird": "prio"]
        #expect(RowActionMigration.pendingValues(stored: { stored[$0] }).isEmpty)
    }

    @Test func migratedValuesLoadIntoTheSettings() {
        let defaults = TestDefaults.fresh()
        let legacy: [String: Any] = ["monitorShowNoteButton": false]
        for (key, value) in RowActionMigration.pendingValues(stored: { legacy[$0] }) {
            defaults.set(value, forKey: key)
        }
        #expect(RowActionSettings(defaults: defaults).actions == [.rename, .hide])
    }

    @Test func slotsDefaultToRenameNoteHideAndAcceptAnyAction() {
        let defaults = TestDefaults.fresh()
        let settings = RowActionSettings(defaults: defaults)
        #expect(settings.actions == [.rename, .note, .hide])

        settings.binding(for: .first).wrappedValue = .prio
        settings.binding(for: .third).wrappedValue = .prio
        #expect(settings.actions == [.prio, .note, .prio])
        #expect(defaults.string(forKey: "monitorRowActionFirst") == "prio")
    }

    @Test func clearingEverySlotLeavesNoActions() {
        let defaults = TestDefaults.fresh()
        let settings = RowActionSettings(defaults: defaults)
        for position in RowActionPosition.allCases {
            settings.binding(for: position).wrappedValue = nil
        }
        #expect(settings.actions == [])
        #expect(defaults.string(forKey: "monitorRowActionSecond") == "none")
        #expect(RowActionSettings(defaults: defaults).actions == [])
    }

    @Test func prioIsAvailableOnlyInFair() {
        #expect(QueueOrderMode.allCases.filter { SessionRowAction.prio.isAvailable(in: $0) } == [.fair])
        #expect(QueueOrderMode.allCases.allSatisfy { SessionRowAction.hide.isAvailable(in: $0) })
    }

    @Test func actionLabelsAndIconsReflectTheSession() {
        var session = makeSession("row")
        #expect(SessionRowAction.rename.label(for: session) == "Rename session")
        #expect(SessionRowAction.rename.icon(for: session) == "pencil")
        #expect(SessionRowAction.note.label(for: session) == "Add note")
        #expect(SessionRowAction.note.icon(for: session) == "text.bubble")
        #expect(SessionRowAction.hide.label(for: session) == "Hide session")
        #expect(SessionRowAction.hide.icon(for: session) == "eye.slash")
        #expect(SessionRowAction.prio.label(for: session) == "Prioritize session")
        #expect(SessionRowAction.prio.icon(for: session) == "flag")
        session.note = "A note"
        session.disposition.isHidden = true
        session.disposition.isPrioritized = true
        #expect(SessionRowAction.note.label(for: session) == "Edit note")
        #expect(SessionRowAction.note.icon(for: session) == "text.bubble.fill")
        #expect(SessionRowAction.hide.label(for: session) == "Unhide session")
        #expect(SessionRowAction.hide.icon(for: session) == "eye")
        #expect(SessionRowAction.prio.label(for: session) == "Unprioritize session")
        #expect(SessionRowAction.prio.icon(for: session) == "flag.fill")
    }

    @Test(arguments: 0 ... 3, [false, true])
    func actionsFitMinimumRowWithAndWithoutStats(actionCount: Int, statsEnabled: Bool) {
        for insets in [SessionMonitorRowLayout.listInsets, SessionMonitorRowLayout.scrollInsets] {
            let height = SessionRowGeometry.controlAreaHeight(
                contentHeight: SessionMonitorRowLayout.contentMinHeight,
                statsEnabled: statsEnabled,
                rowVerticalPadding: insets.vertical
            )
            let metrics = SessionRowActionLayout.metrics(actionCount: actionCount, availableHeight: height)
            let stackHeight = metrics.buttonHeight * CGFloat(actionCount)
                + metrics.spacing * CGFloat(max(0, actionCount - 1))
            #expect(stackHeight <= height)
            #expect(metrics.iconSize <= metrics.buttonHeight)
            #expect(metrics.buttonHeight <= SessionRowActionLayout.buttonSize)
            if actionCount > 0 {
                #expect(metrics.buttonHeight >= 12)
                #expect(metrics.iconSize >= 9)
            }
        }
        #expect(SessionMonitorRowLayout.contentMinHeight == 56)
    }

    @Test(arguments: [CGFloat(-10), 0, 1, 1000], [-1, 0, 1, 2, 3])
    func metricsClampUnavailableOrExcessSpace(height: CGFloat, count: Int) {
        let metrics = SessionRowActionLayout.metrics(actionCount: count, availableHeight: height)
        #expect(metrics.buttonHeight >= 0)
        #expect(metrics.iconSize >= 0)
        #expect(metrics.spacing >= 0)
        #expect(metrics.iconSize <= 11)
        let occupied = metrics.buttonHeight * CGFloat(max(0, count))
            + metrics.spacing * CGFloat(max(0, count - 1))
        #expect(occupied <= max(0, height))
        if height <= 0 || count <= 0 {
            #expect(metrics == SessionRowActionLayout.Metrics(buttonHeight: 0, iconSize: 0, spacing: 0))
        }
    }

    @Test func actionRailUsesTheOuterTopPaddingWithoutMovingTheStateBadge() {
        #expect(SessionRowActionLayout.topOffset(rowVerticalPadding: SessionMonitorRowLayout.listInsets.vertical) == -4)
        #expect(SessionRowActionLayout
            .topOffset(rowVerticalPadding: SessionMonitorRowLayout.scrollInsets.vertical) == -8)
        #expect(SessionRowActionLayout.topOffset(rowVerticalPadding: -4) == 0)
    }
}

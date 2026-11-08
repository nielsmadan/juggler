import CoreGraphics
import Foundation
@testable import Juggler
import SwiftUI
import Testing

@MainActor
struct SessionRowActionTests {
    @Test(arguments: 0 ..< 8)
    func everyActionVisibilityCombinationRetainsItsOrder(mask: Int) {
        let actions = SessionRowAction.visible(rename: mask & 1 != 0, note: mask & 2 != 0, hide: mask & 4 != 0)
        let expected: [SessionRowAction] = switch mask {
        case 0: []
        case 1: [.rename]
        case 2: [.note]
        case 3: [.rename, .note]
        case 4: [.hide]
        case 5: [.rename, .hide]
        case 6: [.note, .hide]
        default: [.rename, .note, .hide]
        }
        #expect(actions == expected)
    }

    @Test func actionLabelsAndIconsReflectTheSession() {
        var session = makeSession("row")
        #expect(SessionRowAction.rename.label(for: session) == "Rename session")
        #expect(SessionRowAction.rename.icon(for: session) == "pencil")
        #expect(SessionRowAction.note.label(for: session) == "Add note")
        #expect(SessionRowAction.note.icon(for: session) == "text.bubble")
        #expect(SessionRowAction.hide.label(for: session) == "Hide session")
        #expect(SessionRowAction.hide.icon(for: session) == "eye.slash")
        session.note = "A note"
        session.disposition.isHidden = true
        #expect(SessionRowAction.note.label(for: session) == "Edit note")
        #expect(SessionRowAction.note.icon(for: session) == "text.bubble.fill")
        #expect(SessionRowAction.hide.label(for: session) == "Unhide session")
        #expect(SessionRowAction.hide.icon(for: session) == "eye")
    }

    @Test func hideSettingDefaultsOnAndPersistsIndependently() {
        let defaults = TestDefaults.fresh()
        defaults.set(false, forKey: AppStorageKeys.monitorShowRenameButton)
        let settings = RowActionSettings(defaults: defaults)
        #expect(AppStorageKeys.monitorShowHideButton == "monitorShowHideButton")
        #expect(settings.actions == [.note, .hide])
        settings.binding(for: .hide).wrappedValue = false
        #expect(defaults.bool(forKey: AppStorageKeys.monitorShowHideButton) == false)
        #expect(settings.actions == [.note])
        settings.binding(for: .rename).wrappedValue = true
        #expect(settings.actions == [.rename, .note])
        settings.binding(for: .hide).wrappedValue = true
        #expect(settings.actions == [.rename, .note, .hide])
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

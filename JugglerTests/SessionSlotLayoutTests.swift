import CoreGraphics
@testable import Juggler
import Testing

@Suite("SessionRowGeometry")
struct SessionRowGeometryTests {
    private let todayOnly: CGFloat = 65
    private let turnAndToday: CGFloat = 130
    private let listInsets = SessionMonitorRowLayout.listInsets
    private let scrollInsets = SessionMonitorRowLayout.scrollInsets

    @Test func listRow_withoutTurnTab() {
        let reserves = SessionRowGeometry.slotReserves(
            cornerWidth: todayOnly,
            statsEnabled: true,
            rowHorizontalPadding: listInsets.horizontal,
            showsActions: true
        )
        #expect(reserves == SlotTrailingReserves(top: 94, bottom: 94))
    }

    @Test func listRow_withTurnTab() {
        let reserves = SessionRowGeometry.slotReserves(
            cornerWidth: turnAndToday,
            statsEnabled: true,
            rowHorizontalPadding: listInsets.horizontal,
            showsActions: true
        )
        #expect(reserves == SlotTrailingReserves(top: 94, bottom: 134))
    }

    @Test func scrollViewRow_withoutTurnTab() {
        let reserves = SessionRowGeometry.slotReserves(
            cornerWidth: todayOnly,
            statsEnabled: true,
            rowHorizontalPadding: scrollInsets.horizontal,
            showsActions: true
        )
        #expect(reserves == SlotTrailingReserves(top: 78, bottom: 78))
    }

    @Test func scrollViewRow_withTurnTab() {
        let reserves = SessionRowGeometry.slotReserves(
            cornerWidth: turnAndToday,
            statsEnabled: true,
            rowHorizontalPadding: scrollInsets.horizontal,
            showsActions: true
        )
        #expect(reserves == SlotTrailingReserves(top: 78, bottom: 118))
    }

    @Test func statsOff_reservesControlsAcrossBothRows() {
        let list = SessionRowGeometry.slotReserves(
            cornerWidth: turnAndToday,
            statsEnabled: false,
            rowHorizontalPadding: listInsets.horizontal,
            showsActions: true
        )
        let scroll = SessionRowGeometry.slotReserves(
            cornerWidth: turnAndToday,
            statsEnabled: false,
            rowHorizontalPadding: scrollInsets.horizontal,
            showsActions: true
        )
        #expect(list == SlotTrailingReserves(top: 94, bottom: 94))
        #expect(scroll == SlotTrailingReserves(top: 78, bottom: 78))
    }

    @Test func hiddenActions_releaseTheirTrailingSpace() {
        let reserves = [false, true].map { showsActions in
            SessionRowGeometry.slotReserves(
                cornerWidth: todayOnly,
                statsEnabled: false,
                rowHorizontalPadding: listInsets.horizontal,
                showsActions: showsActions
            )
        }
        #expect(reserves.map(\.top) == [74, 94])
        #expect(reserves.map(\.bottom) == [74, 94])
    }

    @Test func actionVisibility_preservesWiderStatsCornerReserve() {
        let reserves = [false, true].map { showsActions in
            SessionRowGeometry.slotReserves(
                cornerWidth: turnAndToday,
                statsEnabled: true,
                rowHorizontalPadding: listInsets.horizontal,
                showsActions: showsActions
            )
        }
        #expect(reserves.map(\.top) == [74, 94])
        #expect(reserves.map(\.bottom) == [134, 134])
    }

    @Test func controlArea_excludesStatsCornerOverlap() {
        let listHeight = SessionRowGeometry.controlAreaHeight(
            contentHeight: SessionMonitorRowLayout.contentMinHeight,
            statsEnabled: true,
            rowVerticalPadding: listInsets.vertical
        )
        let scrollHeight = SessionRowGeometry.controlAreaHeight(
            contentHeight: SessionMonitorRowLayout.contentMinHeight,
            statsEnabled: true,
            rowVerticalPadding: scrollInsets.vertical
        )
        let statsOffHeight = SessionRowGeometry.controlAreaHeight(
            contentHeight: SessionMonitorRowLayout.contentMinHeight,
            statsEnabled: false,
            rowVerticalPadding: listInsets.vertical
        )
        #expect(listHeight == 40)
        #expect(scrollHeight == 44)
        #expect(statsOffHeight == SessionMonitorRowLayout.contentMinHeight)
    }
}

@Suite("SessionSlotGridLayout")
struct SessionSlotGridLayoutTests {
    @Test func twoColumns_splitWidthMinusSpacing() {
        #expect(SessionSlotGridLayout.columnWidth(totalWidth: 400, spacing: 12, count: 2) == 194)
        #expect(SessionSlotGridLayout.columnOffsets(totalWidth: 400, spacing: 12, count: 2) == [0, 206])
    }

    @Test func singleColumn_takesFullWidth() {
        #expect(SessionSlotGridLayout.columnWidth(totalWidth: 300, spacing: 12, count: 1) == 300)
        #expect(SessionSlotGridLayout.columnOffsets(totalWidth: 300, spacing: 12, count: 1) == [0])
    }

    @Test func noColumns_haveNoWidthOrOffsets() {
        #expect(SessionSlotGridLayout.columnWidth(totalWidth: 300, spacing: 12, count: 0) == 0)
        #expect(SessionSlotGridLayout.columnOffsets(totalWidth: 300, spacing: 12, count: 0) == [])
    }

    @Test func widthNarrowerThanSpacing_clampsColumnsToZero() {
        #expect(SessionSlotGridLayout.columnWidth(totalWidth: 8, spacing: 12, count: 2) == 0)
        #expect(SessionSlotGridLayout.columnOffsets(totalWidth: 8, spacing: 12, count: 2) == [0, 12])
    }

    @Test func idealWidth_isWidestColumnTimesCountPlusSpacing() {
        #expect(SessionSlotGridLayout.idealWidth(columnIdealWidths: [80, 120], spacing: 12) == 252)
        #expect(SessionSlotGridLayout.idealWidth(columnIdealWidths: [80], spacing: 12) == 80)
        #expect(SessionSlotGridLayout.idealWidth(columnIdealWidths: [], spacing: 12) == 0)
    }

    @Test func trailingCell_fitsDownToMinimumWidth() {
        #expect(SessionSlotGridLayout.trailingCellFits(gridWidth: 400, spacing: 12, reserve: 91))
        #expect(SessionSlotGridLayout.trailingCellFits(gridWidth: 400, spacing: 12, reserve: 154))
    }

    @Test func trailingCell_belowMinimumWidthDoesNotFit() {
        #expect(SessionSlotGridLayout.trailingCellFits(gridWidth: 400, spacing: 12, reserve: 155) == false)
        #expect(SessionSlotGridLayout.trailingCellFits(gridWidth: 0, spacing: 12, reserve: 0) == false)
    }

    @Test func trailingCell_fitUsesTheGivenSpacing() {
        #expect(SessionSlotGridLayout.trailingCellFits(gridWidth: 400, spacing: 20, reserve: 154) == false)
        #expect(SessionSlotGridLayout.trailingCellFits(gridWidth: 400, spacing: 20, reserve: 150))
    }
}

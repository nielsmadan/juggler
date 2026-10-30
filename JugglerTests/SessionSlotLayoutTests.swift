import CoreGraphics
@testable import Juggler
import Testing

@Suite("SessionRowGeometry")
struct SessionRowGeometryTests {
    private let todayOnly: CGFloat = 65
    private let turnAndToday: CGFloat = 130

    @Test func listRow_withoutTurnTab() {
        let reserves = SessionRowGeometry.slotReserves(
            todayTabWidth: todayOnly,
            cornerWidth: todayOnly,
            statsEnabled: true,
            rowHorizontalPadding: 0
        )
        #expect(reserves == SlotTrailingReserves(badge: 91, corner: 69))
    }

    @Test func listRow_withTurnTab() {
        let reserves = SessionRowGeometry.slotReserves(
            todayTabWidth: todayOnly,
            cornerWidth: turnAndToday,
            statsEnabled: true,
            rowHorizontalPadding: 0
        )
        #expect(reserves == SlotTrailingReserves(badge: 91, corner: 134))
    }

    @Test func scrollViewRow_withoutTurnTab() {
        let reserves = SessionRowGeometry.slotReserves(
            todayTabWidth: todayOnly,
            cornerWidth: todayOnly,
            statsEnabled: true,
            rowHorizontalPadding: 16
        )
        #expect(reserves == SlotTrailingReserves(badge: 75, corner: 53))
    }

    @Test func scrollViewRow_withTurnTab() {
        let reserves = SessionRowGeometry.slotReserves(
            todayTabWidth: todayOnly,
            cornerWidth: turnAndToday,
            statsEnabled: true,
            rowHorizontalPadding: 16
        )
        #expect(reserves == SlotTrailingReserves(badge: 75, corner: 118))
    }

    @Test func statsOff_reservesOnlyTheBadge() {
        let list = SessionRowGeometry.slotReserves(
            todayTabWidth: todayOnly,
            cornerWidth: turnAndToday,
            statsEnabled: false,
            rowHorizontalPadding: 0
        )
        let scroll = SessionRowGeometry.slotReserves(
            todayTabWidth: todayOnly,
            cornerWidth: turnAndToday,
            statsEnabled: false,
            rowHorizontalPadding: 16
        )
        #expect(list == SlotTrailingReserves(badge: 91, corner: 0))
        #expect(scroll == SlotTrailingReserves(badge: 75, corner: 0))
    }

    @Test func wideTodayTab_shiftsBadgeLeftAndGrowsTopReserve() {
        let offset = SessionRowGeometry.stateBadgeOffset(todayTabWidth: 80, rowHorizontalPadding: 0)
        let reserves = SessionRowGeometry.slotReserves(
            todayTabWidth: 80,
            cornerWidth: 80,
            statsEnabled: true,
            rowHorizontalPadding: 0
        )
        #expect(offset == -32)
        #expect(reserves.badge == 106)
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

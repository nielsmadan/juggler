import CoreGraphics
import Foundation

nonisolated enum SessionSlotGridLayout {
    static let columnSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 4
    static let minimumTrailingWidth: CGFloat = 40
    static let cornerGap: CGFloat = 4
    static let runTimeRefreshInterval: TimeInterval = 30

    static func columnWidth(totalWidth: CGFloat, spacing: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return max(0, (totalWidth - spacing * CGFloat(count - 1)) / CGFloat(count))
    }

    static func columnOffsets(totalWidth: CGFloat, spacing: CGFloat, count: Int) -> [CGFloat] {
        let width = columnWidth(totalWidth: totalWidth, spacing: spacing, count: count)
        return (0 ..< max(0, count)).map { CGFloat($0) * (width + spacing) }
    }

    static func idealWidth(columnIdealWidths: [CGFloat], spacing: CGFloat) -> CGFloat {
        let widest = columnIdealWidths.max() ?? 0
        return widest * CGFloat(columnIdealWidths.count) + spacing * CGFloat(max(0, columnIdealWidths.count - 1))
    }

    static func trailingCellFits(gridWidth: CGFloat, spacing: CGFloat, reserve: CGFloat) -> Bool {
        columnWidth(totalWidth: gridWidth, spacing: spacing, count: 2) - reserve >= minimumTrailingWidth
    }
}

struct SlotTrailingReserves: Equatable {
    let badge: CGFloat
    let corner: CGFloat
}

enum SessionRowGeometry {
    // Moves the badge from its natural center to the Today tab's diagonal apex.
    static func stateBadgeOffset(todayTabWidth: CGFloat, rowHorizontalPadding: CGFloat) -> CGFloat {
        BusyStatsCornerLayout.tabDiagonalOffset + rowHorizontalPadding + StateBadgeLayout.centerXFromRight
            - todayTabWidth
    }

    static func slotReserves(
        todayTabWidth: CGFloat,
        cornerWidth: CGFloat,
        statsEnabled: Bool,
        rowHorizontalPadding: CGFloat
    ) -> SlotTrailingReserves {
        let badgeOffset = stateBadgeOffset(todayTabWidth: todayTabWidth, rowHorizontalPadding: rowHorizontalPadding)
        let cornerOverlap = max(0, cornerWidth - rowHorizontalPadding) + SessionSlotGridLayout.cornerGap
        return SlotTrailingReserves(
            badge: StateBadgeLayout.frameWidth + StateBadgeLayout.trailingPadding - badgeOffset,
            corner: statsEnabled ? cornerOverlap : 0
        )
    }
}

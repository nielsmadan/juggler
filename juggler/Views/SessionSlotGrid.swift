import SwiftUI

struct LiveSessionSlotGrid: View {
    let slots: [RowSlotPosition: RowSlot]
    let resolve: (Date) -> ResolvedSlotGrid
    let reserves: SlotTrailingReserves

    var body: some View {
        if slots.values.contains(.runTime) {
            TimelineView(.periodic(from: .now, by: SessionSlotGridLayout.runTimeRefreshInterval)) { context in
                SessionSlotGrid(grid: resolve(context.date), reserves: reserves)
                    .equatable()
            }
        } else {
            SessionSlotGrid(grid: resolve(Date()), reserves: reserves)
                .equatable()
        }
    }
}

struct SessionSlotGrid: View, Equatable {
    let grid: ResolvedSlotGrid
    let reserves: SlotTrailingReserves

    @State private var gridWidth: CGFloat = 0

    private let columns = EqualColumnsLayout(spacing: SessionSlotGridLayout.columnSpacing)

    private var rows: [ResolvedSlotRow] {
        [grid.top, grid.bottom].compactMap { $0 }
    }

    static func == (lhs: SessionSlotGrid, rhs: SessionSlotGrid) -> Bool {
        lhs.grid == rhs.grid && lhs.reserves == rhs.reserves
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: SessionSlotGridLayout.rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    columns {
                        leadingCell(row.leading)
                        trailingCell(row.trailing, reserve: index == 0 ? reserves.badge : reserves.corner)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                if gridWidth != width { gridWidth = width }
            }
        }
    }

    @ViewBuilder
    private func leadingCell(_ cell: ResolvedSlot?) -> some View {
        if let cell {
            SlotCellLabel(slot: cell.slot, text: cell.text)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    @ViewBuilder
    private func trailingCell(_ cell: ResolvedSlot?, reserve: CGFloat) -> some View {
        if let cell {
            if SessionSlotGridLayout.trailingCellFits(
                gridWidth: gridWidth,
                spacing: columns.spacing,
                reserve: reserve
            ) {
                SlotCellLabel(slot: cell.slot, text: cell.text)
                    .padding(.trailing, reserve)
            } else {
                SlotCellLabel(slot: cell.slot, text: nil)
                    .overlay {
                        if let text = cell.text {
                            Color.clear
                                .contentShape(Rectangle())
                                .help(text)
                        }
                    }
            }
        } else {
            Color.clear.frame(height: 0)
        }
    }
}

private struct SlotCellLabel: View {
    let slot: RowSlot
    let text: String?

    var body: some View {
        if let text {
            label(text)
                .help(text)
        } else {
            label(" ")
                .hidden()
        }
    }

    private func label(_ text: String) -> some View {
        Label(text, systemImage: slot.systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(slot == .folderPath ? .middle : .tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EqualColumnsLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? SessionSlotGridLayout.idealWidth(
            columnIdealWidths: subviews.map { $0.sizeThatFits(.unspecified).width },
            spacing: spacing
        )
        let column = SessionSlotGridLayout.columnWidth(totalWidth: width, spacing: spacing, count: subviews.count)
        let height = subviews
            .map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let column = SessionSlotGridLayout.columnWidth(
            totalWidth: bounds.width,
            spacing: spacing,
            count: subviews.count
        )
        let offsets = SessionSlotGridLayout.columnOffsets(
            totalWidth: bounds.width,
            spacing: spacing,
            count: subviews.count
        )
        for (subview, offset) in zip(subviews, offsets) {
            subview.place(
                at: CGPoint(x: bounds.minX + offset, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: column, height: bounds.height)
            )
        }
    }
}

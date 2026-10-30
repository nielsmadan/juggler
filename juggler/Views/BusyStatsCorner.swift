import SwiftUI

nonisolated struct BusyStatsCornerWidths: Equatable, Sendable {
    var todayTab: CGFloat = 0
    var corner: CGFloat = 0
}

/// Reports the rendered widths of the Today tab and the whole corner, so the row's state badge
/// can align with the Today tab's diagonal apex and the slot grid can clear the corner.
struct BusyStatsCornerWidthsKey: PreferenceKey {
    static let defaultValue = BusyStatsCornerWidths()
    static func reduce(value: inout BusyStatsCornerWidths, nextValue: () -> BusyStatsCornerWidths) {
        let next = nextValue()
        if next.todayTab > 0 { value.todayTab = next.todayTab }
        if next.corner > 0 { value.corner = next.corner }
    }
}

/// Today is rendered last so its diagonal left edge overlays the Turn tab beneath it.
struct BusyStatsCorner: View {
    let session: Session
    let highlightColor: Color
    let isActive: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            HStack(spacing: -BusyStatsCornerLayout.tabOverlap) {
                if let turn = session.currentWorkingDuration {
                    StatsTab(
                        label: "Turn",
                        value: SessionStatsFormatter.formatDuration(turn),
                        icon: "stopwatch",
                        background: turnBackground,
                        foreground: textColor,
                        borderColor: borderColor,
                        trailingPadding: 12
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                StatsTab(
                    label: "Today",
                    value: SessionStatsFormatter.formatDuration(session.busyTimeTodayLive),
                    icon: "calendar",
                    background: todayBackground,
                    foreground: textColor,
                    borderColor: borderColor
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: BusyStatsCornerWidthsKey.self,
                            value: BusyStatsCornerWidths(todayTab: geo.size.width)
                        )
                    }
                )
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: BusyStatsCornerWidthsKey.self,
                        value: BusyStatsCornerWidths(corner: geo.size.width)
                    )
                }
            )
            .animation(.easeInOut(duration: 0.25), value: session.currentWorkingDuration != nil)
        }
    }

    private var turnBackground: Color {
        isActive ? highlightColor.opacity(0.65) : Color.black
    }

    private var todayBackground: Color {
        isActive ? highlightColor : Color(white: 0.08)
    }

    private var textColor: Color {
        isActive ? Color.black : Color(white: 0.92)
    }

    private var borderColor: Color {
        isActive ? highlightColor : Color(white: 0.35)
    }
}

private struct StatsTab: View {
    let label: String
    let value: String
    let icon: String
    let background: Color
    let foreground: Color
    let borderColor: Color
    var trailingPadding: CGFloat = 8

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 11, height: 11)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 34)
        }
        .padding(.leading, BusyStatsCornerLayout.tabDiagonalOffset + 4)
        .padding(.trailing, trailingPadding)
        .frame(height: BusyStatsCornerLayout.tabHeight)
        .foregroundStyle(foreground)
        .background(background)
        .clipShape(TabShape(cut: BusyStatsCornerLayout.tabDiagonalOffset))
        .overlay(TabBorderShape(cut: BusyStatsCornerLayout.tabDiagonalOffset).stroke(borderColor, lineWidth: 1))
        .help(label)
    }
}

/// Trapezoid: full rectangle minus a triangular notch cut out of the top-left
/// corner, producing a diagonal left edge.
private struct TabShape: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: cut, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Bottom and right edges are omitted so the tab reads as a shelf resting on the row's
/// bottom edge rather than a fully enclosing frame.
private struct TabBorderShape: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: cut, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        return path
    }
}

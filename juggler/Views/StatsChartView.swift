import Combine
import SwiftUI

/// Bar chart of busy time per day, shown at the bottom of the monitor window.
/// Each bar is one day's total busy time (summed across sessions). Today is the
/// rightmost bar and grows live; older days fall off the left edge.
struct StatsChartView: View {
    @Environment(SessionManager.self) private var sessionManager
    @AppStorage(AppStorageKeys.statsUseCyclingColors) private var useCyclingColors = true
    @AppStorage(AppStorageKeys.statsBarColorRed) private var barColorRed = 255.0
    @AppStorage(AppStorageKeys.statsBarColorGreen) private var barColorGreen = 165.0
    @AppStorage(AppStorageKeys.statsBarColorBlue) private var barColorBlue = 0.0

    /// Fixed anchor for stable per-date color assignment.
    private static let referenceDate = Date(timeIntervalSince1970: 0)

    /// Drives midnight-rollover detection. `@State` so it is created once and
    /// survives view re-renders; mutation happens in `.onReceive`, never in `body`.
    @State private var rolloverTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private struct DisplayBar: Identifiable {
        let id: String
        let date: Date
        let seconds: TimeInterval
        let isToday: Bool
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            GeometryReader { geo in
                chart(width: geo.size.width)
            }
        }
        .frame(height: StatsChart.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(rolloverTimer) { _ in
            sessionManager.handleDayRolloverIfNeeded(now: Date())
        }
    }

    @ViewBuilder
    private func chart(width: CGFloat) -> some View {
        let entries = displayEntries()
        let contentWidth = max(width - 24, 0) // 12pt horizontal padding each side
        let result = StatsBarLayout.layout(
            availableWidth: contentWidth,
            dayCount: entries.count,
            minWidth: StatsChart.barMinWidth,
            maxWidth: StatsChart.barMaxWidth,
            gap: StatsChart.barGap
        )
        let visible = Array(entries.suffix(result.count))
        let maxSeconds = max(visible.map(\.seconds).max() ?? 1, 1)

        ZStack(alignment: .topLeading) {
            HStack(alignment: .bottom, spacing: StatsChart.barGap) {
                ForEach(visible) { bar in
                    barView(bar, barWidth: result.barWidth, maxSeconds: maxSeconds)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            overlayText
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private func barView(_ bar: DisplayBar, barWidth: CGFloat, maxSeconds: TimeInterval) -> some View {
        GeometryReader { geo in
            let fraction = CGFloat(bar.seconds / maxSeconds)
            let barHeight = max(geo.size.height * fraction, StatsChart.barMinHeight)
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    UnevenRoundedRectangle(
                        topLeadingRadius: 2, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: 2
                    )
                    .fill(barColor(for: bar))
                    .frame(height: barHeight)
                }
                // Label sits at the bottom, drawn on top of the bar (and the
                // background below, for very short bars). Ink + opposite-tone
                // halo are chosen from the bar's own luminance so the text stays
                // legible over bright bars (green, yellow) as well as dark ones.
                let ink = labelInk(for: bar)
                Text(SessionStatsCalculator.formatDuration(bar.seconds))
                    .font(.system(size: 11))
                    .foregroundStyle(ink.ink)
                    .lineLimit(1)
                    .shadow(color: ink.halo.opacity(0.85), radius: 1, x: 0, y: 0)
                    .shadow(color: ink.halo.opacity(0.55), radius: 2.5, x: 0, y: 1)
                    .padding(.bottom, 3)
            }
        }
        .frame(width: barWidth)
    }

    /// Label ink + halo chosen from the bar's luminance: black ink over bright
    /// bars (green, yellow), white over dark ones, with an opposite-tone halo so
    /// the text also reads where it spills onto the window background.
    private func labelInk(for bar: DisplayBar) -> (ink: Color, halo: Color) {
        let rgb = barRGB(for: bar)
        // Relative luminance (Rec. 709 weights).
        let luminance = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
        return luminance > 0.6 ? (.black, .white) : (.white, .black)
    }

    private var overlayText: some View {
        HStack(alignment: .top) {
            Text("\(workingCount)/\(sessionManager.sessions.count) busy")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("busy time by day")
                .font(.system(size: 10))
                .opacity(0.65)
                .padding(.trailing, 6)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
    }

    // MARK: - Data

    private var workingCount: Int {
        sessionManager.sessions.filter { $0.state == .working || $0.state == .compacting }.count
    }

    /// Live today total: persisted busy time + every in-progress turn.
    private func liveTodaySeconds() -> TimeInterval {
        sessionManager.dailyStats.todayBusySeconds
            + sessionManager.sessions.reduce(0) { $0 + ($1.currentWorkingDuration ?? 0) }
    }

    /// Days to render, oldest -> newest. Today is always present as the last
    /// entry (even at 0) so the chart has a stable right anchor.
    private func displayEntries() -> [DisplayBar] {
        let todayKey = DailyStatsStore.dayKey(for: Date())
        var bars = sessionManager.dailyStats.recentDays(limit: 60).map { entry in
            DisplayBar(
                id: entry.key, date: entry.date,
                seconds: entry.seconds, isToday: entry.key == todayKey
            )
        }
        let liveToday = liveTodaySeconds()
        if let index = bars.firstIndex(where: { $0.isToday }) {
            let existing = bars[index]
            bars[index] = DisplayBar(
                id: existing.id, date: existing.date, seconds: liveToday, isToday: true
            )
        } else {
            bars.append(DisplayBar(
                id: todayKey,
                date: Calendar.current.startOfDay(for: Date()),
                seconds: liveToday,
                isToday: true
            ))
        }
        return bars
    }

    // MARK: - Color

    private func barColor(for bar: DisplayBar) -> Color {
        let rgb = barRGB(for: bar)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// Normalized (0...1) RGB of a bar's fill — the single source of truth for
    /// both the fill color and the luminance-based label ink.
    private func barRGB(for bar: DisplayBar) -> (r: Double, g: Double, b: Double) {
        let factor = bar.isToday ? 1.0 : StatsChart.barDimFactor
        if useCyclingColors {
            let count = CyclingColors.paletteRGB.count
            let rgb = CyclingColors.paletteRGB[colorIndex(for: bar.date) % count]
            return (Double(rgb[0]) * factor / 255,
                    Double(rgb[1]) * factor / 255,
                    Double(rgb[2]) * factor / 255)
        } else {
            return (barColorRed * factor / 255,
                    barColorGreen * factor / 255,
                    barColorBlue * factor / 255)
        }
    }

    /// Stable per-date color index so resizing the window never reshuffles hues.
    private func colorIndex(for date: Date) -> Int {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let days = Calendar.current.dateComponents(
            [.day], from: Self.referenceDate, to: startOfDay
        ).day ?? 0
        return ((days % 5) + 5) % 5
    }
}

import Combine
import SwiftUI

/// Bar chart of busy time per day, shown at the bottom of the monitor window.
/// Each bar is one day's total busy time (summed across sessions). Today is the
/// rightmost bar and grows live; older days fall off the left edge.
struct StatsChartView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.colorScheme) private var colorScheme
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
                // halo adapt to appearance so it stays legible over both the
                // window background and any bar color.
                Text(SessionStatsCalculator.formatDuration(bar.seconds))
                    .font(.system(size: 10))
                    .foregroundStyle(labelInk)
                    .lineLimit(1)
                    .shadow(color: labelHalo.opacity(0.85), radius: 1, x: 0, y: 0)
                    .shadow(color: labelHalo.opacity(0.55), radius: 2.5, x: 0, y: 1)
                    .padding(.bottom, 3)
            }
        }
        .frame(width: barWidth)
    }

    /// Label ink: white in dark mode, black in light mode.
    private var labelInk: Color { colorScheme == .dark ? .white : .black }
    /// Opposite-tone halo so the ink reads over any background behind it.
    private var labelHalo: Color { colorScheme == .dark ? .black : .white }

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
        let factor = StatsChart.barDimFactor
        if useCyclingColors {
            let index = colorIndex(for: bar.date)
            return bar.isToday
                ? CyclingColors.color(at: index)
                : CyclingColors.dimColor(at: index, factor: factor)
        } else {
            let full = Color(
                red: barColorRed / 255, green: barColorGreen / 255, blue: barColorBlue / 255
            )
            let dim = Color(
                red: barColorRed * factor / 255,
                green: barColorGreen * factor / 255,
                blue: barColorBlue * factor / 255
            )
            return bar.isToday ? full : dim
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

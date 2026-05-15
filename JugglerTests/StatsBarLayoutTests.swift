import CoreGraphics
@testable import Juggler
import Testing

@Suite("StatsBarLayout")
struct StatsBarLayoutTests {
    // gap 6, min 56, max 80 — same constants the chart uses.
    private func layout(width: CGFloat, days: Int) -> (count: Int, barWidth: CGFloat) {
        StatsBarLayout.layout(availableWidth: width, dayCount: days, minWidth: 56, maxWidth: 80, gap: 6)
    }

    @Test func emptyData_returnsZeroBars() {
        let result = layout(width: 400, days: 0)
        #expect(result.count == 0)
    }

    @Test func tinyWidth_stillShowsOneBar() {
        // Narrower than one min-width bar — we always show today.
        let result = layout(width: 20, days: 5)
        #expect(result.count == 1)
    }

    @Test func countIsCappedByAvailableData() {
        // Plenty of width, only 3 days of data.
        let result = layout(width: 2000, days: 3)
        #expect(result.count == 3)
    }

    @Test func barsStretchToFillWidth() {
        // 3 bars at min 56 + 2 gaps of 6 = 180. Give 240 of width: 3 bars still fit,
        // not enough for a 4th (would need 56+6 = 62 more), so the 3 stretch.
        let result = layout(width: 240, days: 10)
        #expect(result.count == 3)
        // (240 - 2*6) / 3 = 76 — between min (56) and max (80).
        #expect(abs(result.barWidth - 76) < 0.001)
    }

    @Test func barWidthNeverExceedsMax() {
        // Lots of width, few days — bars cap at maxWidth, leftover space unused.
        let result = layout(width: 2000, days: 2)
        #expect(result.count == 2)
        #expect(result.barWidth == 80)
    }

    @Test func barWidthNeverBelowMinForExactFit() {
        // Exactly 4 min-width bars + 3 gaps = 4*56 + 3*6 = 242.
        let result = layout(width: 242, days: 10)
        #expect(result.count == 4)
        #expect(abs(result.barWidth - 56) < 0.001)
    }

    @Test func addsABarWhenWidthCrossesThreshold() {
        // 242 -> 4 bars. 242 + 62 (one more min bar + gap) = 304 -> 5 bars.
        #expect(layout(width: 242, days: 10).count == 4)
        #expect(layout(width: 304, days: 10).count == 5)
    }
}

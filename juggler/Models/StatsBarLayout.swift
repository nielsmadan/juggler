import CoreGraphics

/// Pure layout math for the busy-time bar chart.
///
/// Bars are laid out from the right (today is always rightmost). The number of
/// bars is "however many fit" at `minWidth`, capped by how much history exists.
/// Once the count is fixed, every bar is the same width: the available space is
/// divided evenly, then clamped to `[minWidth, maxWidth]`. When the clamp hits
/// `maxWidth` (few days, wide window) the leftover space is simply unused.
enum StatsBarLayout {
    static func layout(
        availableWidth: CGFloat,
        dayCount: Int,
        minWidth: CGFloat,
        maxWidth: CGFloat,
        gap: CGFloat
    ) -> (count: Int, barWidth: CGFloat) {
        guard dayCount > 0, availableWidth > 0, minWidth > 0 else {
            return (0, minWidth)
        }

        // How many min-width bars fit: n*minWidth + (n-1)*gap <= availableWidth
        let fit = Int(((availableWidth + gap) / (minWidth + gap)).rounded(.down))
        let count = max(1, min(dayCount, fit))

        // Divide the width evenly among `count` bars, then clamp.
        let raw = (availableWidth - CGFloat(count - 1) * gap) / CGFloat(count)
        let barWidth = min(max(raw, minWidth), maxWidth)

        return (count, barWidth)
    }
}

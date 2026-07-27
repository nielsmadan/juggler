import CoreGraphics

// Bars run right-to-left with today rightmost, and all share one width; when the
// clamp hits `maxWidth` the leftover space is left unused.
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

        let raw = (availableWidth - CGFloat(count - 1) * gap) / CGFloat(count)
        let barWidth = min(max(raw, minWidth), maxWidth)

        return (count, barWidth)
    }
}

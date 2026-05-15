import SwiftUI

enum CyclingColors {
    static let palette: [Color] = [
        Color(red: 212 / 255, green: 67 / 255, blue: 67 / 255), // #d44343 red
        Color(red: 255 / 255, green: 180 / 255, blue: 0 / 255), // #ffb400 yellow
        Color(red: 144 / 255, green: 104 / 255, blue: 212 / 255), // #9068d4 purple
        Color(red: 75 / 255, green: 177 / 255, blue: 223 / 255), // #4bb1df blue
        Color(red: 158 / 255, green: 212 / 255, blue: 80 / 255) // #9ed450 green
    ]

    static let paletteRGB: [[Int]] = [
        [212, 67, 67],
        [255, 180, 0],
        [144, 104, 212],
        [75, 177, 223],
        [158, 212, 80]
    ]

    // 50% brightness variant for pane backgrounds
    static let darkPaletteRGB: [[Int]] = [
        [106, 34, 34],
        [128, 90, 0],
        [72, 52, 106],
        [38, 89, 112],
        [79, 106, 40]
    ]
}

extension CyclingColors {
    /// Full-strength palette color at `index` (wraps).
    static func color(at index: Int) -> Color {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    /// Palette color at `index` scaled by `factor` (1.0 = full, 0.5 = half-brightness).
    /// `factor` multiplies each RGB channel; values <= 0 produce black.
    static func dimColor(at index: Int, factor: Double) -> Color {
        let count = paletteRGB.count
        let rgb = paletteRGB[((index % count) + count) % count]
        return Color(
            red: Double(rgb[0]) * factor / 255,
            green: Double(rgb[1]) * factor / 255,
            blue: Double(rgb[2]) * factor / 255
        )
    }

    /// 50%-brightness ("dark") palette variant at `index` (wraps).
    /// Kept for pane-background callers; new dim treatments should use `dimColor(at:factor:)`.
    static func darkColor(at index: Int) -> Color {
        dimColor(at: index, factor: 0.5)
    }
}

/// Layout + sizing constants for the busy-time bar chart in the monitor window.
enum StatsChart {
    static let barMinWidth: CGFloat = 56
    static let barMaxWidth: CGFloat = 80
    static let barGap: CGFloat = 6
    static let barMinHeight: CGFloat = 20
    static let height: CGFloat = 104
    /// Brightness factor applied to non-today bars (full-strength * factor).
    /// Lower = more contrast against today's full-strength bar.
    static let barDimFactor: Double = 0.32
}

/// Geometry constants for the per-row Turn / Today corner tabs (see `BusyStatsCorner`).
enum BusyStatsCornerLayout {
    static let tabHeight: CGFloat = 20
    /// Horizontal distance the top-left corner of each tab is shifted right —
    /// creates the slanted left edge.
    static let tabDiagonalOffset: CGFloat = 9
    /// How far the Turn tab tucks underneath the Today tab's diagonal.
    /// Defined as `tabDiagonalOffset` so the tabs kiss at the top without a gap.
    static let tabOverlap: CGFloat = tabDiagonalOffset
}

/// Geometry constants for the session row's state badge (icon + "idle"/"working" label).
enum StateBadgeLayout {
    static let frameWidth: CGFloat = 70
    static let trailingPadding: CGFloat = 4
    /// Distance from a right-anchored badge's center to the row's right edge,
    /// excluding the row's outer horizontal padding.
    static var centerXFromRight: CGFloat { trailingPadding + frameWidth / 2 }
}

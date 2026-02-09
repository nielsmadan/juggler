import SwiftUI

// MARK: - Cycling Colors

enum CyclingColors {
    static let palette: [Color] = [
        Color(red: 212 / 255, green: 67 / 255, blue: 67 / 255), // #d44343 red
        Color(red: 255 / 255, green: 180 / 255, blue: 0 / 255), // #ffb400 yellow
        Color(red: 144 / 255, green: 104 / 255, blue: 212 / 255), // #9068d4 purple
        Color(red: 75 / 255, green: 177 / 255, blue: 223 / 255), // #4bb1df blue
        Color(red: 158 / 255, green: 212 / 255, blue: 80 / 255) // #9ed450 green
    ]

    // Tab bar cycling colors (bright)
    static let paletteRGB: [[Int]] = [
        [212, 67, 67],
        [255, 180, 0],
        [144, 104, 212],
        [75, 177, 223],
        [158, 212, 80]
    ]

    // Pane cycling colors (darker - 50% brightness)
    static let darkPaletteRGB: [[Int]] = [
        [106, 34, 34],
        [128, 90, 0],
        [72, 52, 106],
        [38, 89, 112],
        [79, 106, 40]
    ]
}

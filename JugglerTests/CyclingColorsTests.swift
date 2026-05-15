@testable import Juggler
import SwiftUI
import Testing

@Suite("CyclingColors")
struct CyclingColorsTests {
    @Test func darkColorAt_wrapsIndex() {
        #expect(CyclingColors.darkColor(at: 0) == CyclingColors.darkColor(at: 5))
        #expect(CyclingColors.darkColor(at: -1) == CyclingColors.darkColor(at: 4))
    }

    @Test func darkColorAt_matchesDarkPalette() {
        let rgb = CyclingColors.darkPaletteRGB[2]
        let expected = Color(
            red: Double(rgb[0]) / 255, green: Double(rgb[1]) / 255, blue: Double(rgb[2]) / 255
        )
        #expect(CyclingColors.darkColor(at: 2) == expected)
    }

    @Test func colorAt_wrapsIndex() {
        #expect(CyclingColors.color(at: 0) == CyclingColors.color(at: 5))
    }
}

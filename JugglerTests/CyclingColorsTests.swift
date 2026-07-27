@testable import Juggler
import SwiftUI
import Testing

@Suite("CyclingColors")
struct CyclingColorsTests {
    // darkPaletteRGB is hand-written, so pin it against paletteRGB; channels are rounded, not truncated.
    @Test func darkPaletteRGB_isHalfBrightnessOfPalette() {
        #expect(CyclingColors.darkPaletteRGB.count == CyclingColors.paletteRGB.count)

        for (dark, full) in zip(CyclingColors.darkPaletteRGB, CyclingColors.paletteRGB) {
            for (darkChannel, fullChannel) in zip(dark, full) {
                #expect(abs(Double(darkChannel) - Double(fullChannel) * 0.5) <= 0.5)
            }
        }
    }

    @Test func dimColorAt_wrapsIndex() {
        #expect(CyclingColors.dimColor(at: 0, factor: 0.5) == CyclingColors.dimColor(at: 5, factor: 0.5))
        #expect(CyclingColors.dimColor(at: -1, factor: 0.5) == CyclingColors.dimColor(at: 4, factor: 0.5))
    }

    @Test func colorAt_wrapsIndex() {
        #expect(CyclingColors.color(at: 0) == CyclingColors.color(at: 5))
    }
}

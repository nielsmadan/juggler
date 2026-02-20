//
//  TerminalActivationTests.swift
//  JugglerTests
//

import Foundation
@testable import Juggler
import Testing

// MARK: - buildTabHighlightConfig Tests

@Test func buildTabHighlight_disabled_returnsNil() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: false, useCycling: true, colorIndex: 0, customColor: [255, 0, 0], duration: 2.0
    )
    #expect(config == nil)
}

@Test func buildTabHighlight_cycling_usePaletteColor() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: true, useCycling: true, colorIndex: 0, customColor: [0, 0, 0], duration: 2.0
    )
    #expect(config != nil)
    #expect(config?.color == CyclingColors.paletteRGB[0])
    #expect(config?.duration == 2.0)
}

@Test func buildTabHighlight_notCycling_useCustomColor() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: true, useCycling: false, colorIndex: 0, customColor: [100, 200, 50], duration: 3.0
    )
    #expect(config?.color == [100, 200, 50])
}

@Test func buildTabHighlight_zeroDuration_defaultsToTwo() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: true, useCycling: false, colorIndex: 0, customColor: [0, 0, 0], duration: 0
    )
    #expect(config?.duration == 2.0)
}

@Test func buildTabHighlight_colorIndex_wraps() {
    let config = TerminalActivation.buildTabHighlightConfig(
        enabled: true, useCycling: true, colorIndex: 7, customColor: [0, 0, 0], duration: 1.0
    )
    // 7 % 5 = 2
    #expect(config?.color == CyclingColors.paletteRGB[2])
}

// MARK: - buildPaneHighlightConfig Tests

@Test func buildPaneHighlight_disabled_returnsNil() {
    let config = TerminalActivation.buildPaneHighlightConfig(
        enabled: false, useCycling: true, colorIndex: 0, customColor: [0, 0, 0], duration: 1.0
    )
    #expect(config == nil)
}

@Test func buildPaneHighlight_cycling_useDarkPalette() {
    let config = TerminalActivation.buildPaneHighlightConfig(
        enabled: true, useCycling: true, colorIndex: 0, customColor: [0, 0, 0], duration: 1.0
    )
    #expect(config?.color == CyclingColors.darkPaletteRGB[0])
}

@Test func buildPaneHighlight_zeroDuration_defaultsToOne() {
    let config = TerminalActivation.buildPaneHighlightConfig(
        enabled: true, useCycling: false, colorIndex: 0, customColor: [50, 50, 50], duration: 0
    )
    #expect(config?.duration == 1.0)
}

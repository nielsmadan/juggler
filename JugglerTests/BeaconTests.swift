import Foundation
@testable import Juggler
import Testing

@Suite("Beacon")
struct BeaconTests {
    // MARK: - BeaconPosition Tests

    @Test func beaconPosition_displayName() {
        #expect(BeaconPosition.center.displayName == "Center")
        #expect(BeaconPosition.topLeft.displayName == "Top Left")
        #expect(BeaconPosition.topRight.displayName == "Top Right")
        #expect(BeaconPosition.bottomLeft.displayName == "Bottom Left")
        #expect(BeaconPosition.bottomRight.displayName == "Bottom Right")
    }

    // MARK: - BeaconAnchor Tests

    @Test func beaconAnchor_displayName() {
        #expect(BeaconAnchor.screen.displayName == "Screen")
        #expect(BeaconAnchor.activeWindow.displayName == "Active Window")
    }

    // MARK: - BeaconSize Tests

    @Test func beaconSize_displayName() {
        #expect(BeaconSize.xs.displayName == "XS")
        #expect(BeaconSize.s.displayName == "S")
        #expect(BeaconSize.m.displayName == "M")
        #expect(BeaconSize.l.displayName == "L")
        #expect(BeaconSize.xl.displayName == "XL")
    }

    @Test func beaconSize_fontSize() {
        #expect(BeaconSize.xs.fontSize == 16)
        #expect(BeaconSize.s.fontSize == 22)
        #expect(BeaconSize.m.fontSize == 30)
        #expect(BeaconSize.l.fontSize == 40)
        #expect(BeaconSize.xl.fontSize == 52)
    }

    @Test func beaconSize_horizontalPadding() {
        #expect(BeaconSize.xs.horizontalPadding == 16)
        #expect(BeaconSize.s.horizontalPadding == 24)
        #expect(BeaconSize.m.horizontalPadding == 32)
        #expect(BeaconSize.l.horizontalPadding == 40)
        #expect(BeaconSize.xl.horizontalPadding == 48)
    }

    @Test func beaconSize_verticalPadding() {
        #expect(BeaconSize.xs.verticalPadding == 8)
        #expect(BeaconSize.s.verticalPadding == 12)
        #expect(BeaconSize.m.verticalPadding == 16)
        #expect(BeaconSize.l.verticalPadding == 20)
        #expect(BeaconSize.xl.verticalPadding == 24)
    }

    @Test func beaconSize_minWidth() {
        #expect(BeaconSize.xs.minWidth == 100)
        #expect(BeaconSize.s.minWidth == 150)
        #expect(BeaconSize.m.minWidth == 200)
        #expect(BeaconSize.l.minWidth == 260)
        #expect(BeaconSize.xl.minWidth == 320)
    }
}

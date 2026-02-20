//
//  BeaconPositionCalculatorTests.swift
//  JugglerTests
//

import CoreGraphics
import Foundation
@testable import Juggler
import Testing

@Test func beaconPosition_center() {
    let frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let panel = NSSize(width: 200, height: 60)
    let origin = BeaconPositionCalculator.calculateOrigin(position: .center, referenceFrame: frame, panelSize: panel)
    #expect(origin.x == 400) // (1000/2) - (200/2)
    #expect(origin.y == 370) // (800/2) - (60/2)
}

@Test func beaconPosition_topLeft() {
    let frame = NSRect(x: 100, y: 100, width: 1000, height: 800)
    let panel = NSSize(width: 200, height: 60)
    let origin = BeaconPositionCalculator.calculateOrigin(position: .topLeft, referenceFrame: frame, panelSize: panel)
    #expect(origin.x == 140) // 100 + 40
    #expect(origin.y == 800) // 100 + 800 - 60 - 40
}

@Test func beaconPosition_topRight() {
    let frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let panel = NSSize(width: 200, height: 60)
    let origin = BeaconPositionCalculator.calculateOrigin(position: .topRight, referenceFrame: frame, panelSize: panel)
    #expect(origin.x == 760) // 1000 - 200 - 40
    #expect(origin.y == 700) // 800 - 60 - 40
}

@Test func beaconPosition_bottomLeft() {
    let frame = NSRect(x: 50, y: 50, width: 1000, height: 800)
    let panel = NSSize(width: 200, height: 60)
    let origin = BeaconPositionCalculator.calculateOrigin(
        position: .bottomLeft, referenceFrame: frame, panelSize: panel
    )
    #expect(origin.x == 90) // 50 + 40
    #expect(origin.y == 90) // 50 + 40
}

@Test func beaconPosition_bottomRight() {
    let frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let panel = NSSize(width: 200, height: 60)
    let origin = BeaconPositionCalculator.calculateOrigin(
        position: .bottomRight, referenceFrame: frame, panelSize: panel
    )
    #expect(origin.x == 760) // 1000 - 200 - 40
    #expect(origin.y == 40) // 0 + 40
}

@Test func beaconPosition_customMargin() {
    let frame = NSRect(x: 0, y: 0, width: 500, height: 500)
    let panel = NSSize(width: 100, height: 50)
    let origin = BeaconPositionCalculator.calculateOrigin(
        position: .topLeft, referenceFrame: frame, panelSize: panel, margin: 20
    )
    #expect(origin.x == 20)
    #expect(origin.y == 430) // 500 - 50 - 20
}

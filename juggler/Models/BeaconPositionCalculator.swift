//
//  BeaconPositionCalculator.swift
//  Juggler
//

import CoreGraphics
import Foundation

/// Pure geometry for beacon panel positioning — extracted from BeaconManager for testability.
enum BeaconPositionCalculator {
    static func calculateOrigin(
        position: BeaconPosition,
        referenceFrame: NSRect,
        panelSize: NSSize,
        margin: CGFloat = 40
    ) -> NSPoint {
        switch position {
        case .center:
            NSPoint(
                x: referenceFrame.midX - panelSize.width / 2,
                y: referenceFrame.midY - panelSize.height / 2
            )
        case .topLeft:
            NSPoint(
                x: referenceFrame.minX + margin,
                y: referenceFrame.maxY - panelSize.height - margin
            )
        case .topRight:
            NSPoint(
                x: referenceFrame.maxX - panelSize.width - margin,
                y: referenceFrame.maxY - panelSize.height - margin
            )
        case .bottomLeft:
            NSPoint(
                x: referenceFrame.minX + margin,
                y: referenceFrame.minY + margin
            )
        case .bottomRight:
            NSPoint(
                x: referenceFrame.maxX - panelSize.width - margin,
                y: referenceFrame.minY + margin
            )
        }
    }
}

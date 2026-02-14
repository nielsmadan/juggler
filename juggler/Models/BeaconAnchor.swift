import Foundation

enum BeaconAnchor: String, CaseIterable {
    case screen
    case activeWindow

    var displayName: String {
        switch self {
        case .screen: "Screen"
        case .activeWindow: "Active Window"
        }
    }
}

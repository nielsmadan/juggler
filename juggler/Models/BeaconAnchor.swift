import Foundation

enum BeaconAnchor: String, CaseIterable {
    case screen
    case activeWindow

    static let `default`: BeaconAnchor = .screen

    var displayName: String {
        switch self {
        case .screen: "Screen"
        case .activeWindow: "Active Window"
        }
    }
}

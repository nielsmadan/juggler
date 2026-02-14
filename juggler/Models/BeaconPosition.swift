import Foundation

enum BeaconPosition: String, CaseIterable {
    case center
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var displayName: String {
        switch self {
        case .center: "Center"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        }
    }
}

import Foundation

enum BeaconSize: String, CaseIterable {
    case xs
    case s
    case m
    case l
    case xl

    static let `default`: BeaconSize = .m

    var displayName: String {
        rawValue.uppercased()
    }

    var fontSize: CGFloat {
        switch self {
        case .xs: 16
        case .s: 22
        case .m: 30
        case .l: 40
        case .xl: 52
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .xs: 16
        case .s: 24
        case .m: 32
        case .l: 40
        case .xl: 48
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .xs: 8
        case .s: 12
        case .m: 16
        case .l: 20
        case .xl: 24
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .xs: 100
        case .s: 150
        case .m: 200
        case .l: 260
        case .xl: 320
        }
    }
}

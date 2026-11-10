import SwiftUI

struct PrioMarker: View {
    private static let width: CGFloat = 3

    static func isShown(for session: Session, mode: QueueOrderMode?) -> Bool {
        session.isPrioritized && mode?.supportsPrioritizedSessions == true
    }

    var body: some View {
        Rectangle()
            .fill(Color.orange)
            .frame(width: Self.width)
            .accessibilityLabel("Prio session")
    }
}

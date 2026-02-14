import SwiftUI

struct BeaconContentView: View {
    let sessionName: String
    var size: BeaconSize = .m

    var body: some View {
        Text(sessionName)
            .font(.system(size: size.fontSize, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(minWidth: size.minWidth, maxWidth: 600)
            .background(Color.black)
            .overlay(Rectangle().stroke(Color.white, lineWidth: 2))
            .fixedSize(horizontal: false, vertical: true)
    }
}

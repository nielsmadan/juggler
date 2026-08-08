import SwiftUI

struct BeaconContentView: View {
    let sessionName: String
    var subtitle: String?
    var size: BeaconSize = .m

    var body: some View {
        VStack(spacing: 4) {
            Text(sessionName)
                .font(.system(size: size.fontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: size.subtitleFontSize, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .frame(minWidth: size.minWidth, maxWidth: 600)
        .background(Color.black)
        .overlay(Rectangle().stroke(Color.white, lineWidth: 2))
        .fixedSize(horizontal: false, vertical: true)
    }
}

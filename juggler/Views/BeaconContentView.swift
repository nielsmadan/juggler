import SwiftUI

struct BeaconContentView: View {
    enum ContentRole: Hashable {
        case title
        case note
        case metadata
    }

    struct ContentLine: Equatable, Identifiable {
        let role: ContentRole
        let text: String

        var id: ContentRole { role }
    }

    let sessionName: String
    var note: String?
    var metadata: String?
    var size: BeaconSize = .m

    static func contentLines(sessionName: String, note: String?, metadata: String?) -> [ContentLine] {
        var lines = [ContentLine(role: .title, text: sessionName)]
        if let note {
            lines.append(ContentLine(role: .note, text: note))
        }
        if let metadata {
            lines.append(ContentLine(role: .metadata, text: metadata))
        }
        return lines
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Self.contentLines(sessionName: sessionName, note: note, metadata: metadata)) { line in
                switch line.role {
                case .title:
                    Text(line.text)
                        .font(.system(size: size.fontSize, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                case .note:
                    Text(line.text)
                        .font(.system(size: size.noteFontSize, weight: .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                case .metadata:
                    Text(line.text)
                        .font(.system(
                            size: note == nil ? size.subtitleFontSize : size.metadataFontSize,
                            weight: .regular
                        ))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
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

import SwiftUI

enum ProviderArtwork {
    static func assetName(_ agent: String) -> String {
        switch AgentIdentity.normalize(agent) {
        case "claude": return "ProviderClaude"
        case "cursor": return "ProviderCursor"
        case "grok": return "ProviderGrok"
        default: return "ProviderCodex"
        }
    }

    static func isAvailable(_ agent: String) -> Bool {
        AgentIdentity.knownIds.contains(AgentIdentity.normalize(agent))
    }
}

struct ProviderArtworkImage: View {
    let agent: String
    var size: CGFloat

    var body: some View {
        Image(ProviderArtwork.assetName(agent))
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

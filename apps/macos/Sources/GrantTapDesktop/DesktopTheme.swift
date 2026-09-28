import AppKit
import SwiftUI

enum DesktopTheme {
    static let background = adaptive(light: 0xF2EFE9, dark: 0x121316)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1B1D21)
    static let raised = adaptive(light: 0xFBF9F5, dark: 0x22252A)
    static let ink = adaptive(light: 0x1E1C19, dark: 0xECE9E4)
    static let muted = adaptive(light: 0x7C766C, dark: 0xA5A9B0)
    static let line = adaptive(light: 0xDED8CE, dark: 0x343840)
    static let positive = adaptive(light: 0x3F7A33, dark: 0x93A870)
    static let caution = adaptive(light: 0xB2721A, dark: 0xFFB43D)
    static let danger = adaptive(light: 0xC7362F, dark: 0xFF6A52)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((value >> 16) & 0xff) / 255,
                green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255,
                alpha: 1
            )
        })
    }
}

struct DesktopSectionHeading: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(DesktopTheme.muted)
            Spacer()
            if let count {
                Text(count.formatted())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(title == "Needs You" ? DesktopTheme.danger : DesktopTheme.muted)
            }
        }
    }
}

struct DesktopAgentBadge: View {
    let provider: String?
    var size: CGFloat = 28

    private var normalized: String { provider?.lowercased() ?? "" }
    private var resource: String? {
        switch normalized {
        case "codex": "ProviderCodex"
        case "claude": "ProviderClaude"
        case "cursor": "ProviderCursor"
        case "grok", "grok_bot": "ProviderGrok"
        default: nil
        }
    }
    private var artwork: NSImage? {
        guard let resource else { return nil }
        if let named = NSImage(named: resource) { return named }
        guard let url = Bundle.main.url(forResource: resource, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        Group {
            if let image = artwork {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "sparkle")
                    .resizable().scaledToFit().padding(size * 0.23)
                    .foregroundStyle(DesktopTheme.ink)
                    .background(DesktopTheme.surface)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
        .accessibilityLabel(provider?.capitalized ?? "Agent")
    }
}

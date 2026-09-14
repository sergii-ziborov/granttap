import SwiftUI

/// Design tokens shared by every screen.
///
/// Two ideas carried over from the prototypes:
///  1. The shell is a calm neutral that adapts to light/dark — it never competes.
///  2. Agent surfaces are intentionally distinct; risk colour remains semantic
///     and separate from provider accents, so "dangerous" never reads as
///     "which agent".
enum Theme {

    // MARK: neutrals (light / dark pairs)

    static let bg      = dynamic(light: hex(0xF2EFE9), dark: hex(0x121316))
    static let surface = dynamic(light: hex(0xFFFFFF), dark: hex(0x1B1D21))
    static let raised  = dynamic(light: hex(0xFBF9F5), dark: hex(0x22252A))
    static let ink     = dynamic(light: hex(0x1E1C19), dark: hex(0xECE9E4))
    static let muted   = dynamic(light: hex(0x7C766C), dark: hex(0x8D9198))
    static let line    = dynamic(light: hex(0xDED8CE), dark: hex(0x2E3239))
    static let disabledFill = dynamic(light: hex(0xDED8CE), dark: hex(0x343840))
    static let disabledInk  = dynamic(light: hex(0x5E5A52), dark: hex(0xC4C7CD))

    // MARK: agent identity

    static let claude = dynamic(light: hex(0xC0491F), dark: hex(0xEC6A3C))
    static let codex  = dynamic(light: hex(0x151515), dark: hex(0xF2F2F2))
    static let cursor = dynamic(light: hex(0x5B4BD8), dark: hex(0x9B8CFF))
    static let grok = dynamic(light: hex(0x7A3DB8), dark: hex(0xD08CFF))
    static let claudeCanvas = dynamic(light: hex(0xF6ECE5), dark: hex(0x211713))
    static let codexCanvas = dynamic(light: hex(0xECEDEF), dark: hex(0x101113))
    static let cursorCanvas = dynamic(light: hex(0xEFEDFA), dark: hex(0x171523))
    static let grokCanvas = dynamic(light: hex(0xF4ECF8), dark: hex(0x211522))

    static func accent(for agent: String) -> Color {
        switch AgentIdentity.normalize(agent) {
        case "claude": return claude
        case "cursor": return cursor
        case "grok": return grok
        default: return codex
        }
    }

    static func canvas(for agent: String) -> Color {
        switch AgentIdentity.normalize(agent) {
        case "claude": return claudeCanvas
        case "cursor": return cursorCanvas
        case "grok": return grokCanvas
        default: return codexCanvas
        }
    }

    static func glyphInk(for agent: String) -> Color {
        AgentIdentity.normalize(agent) == "codex"
            ? dynamic(light: hex(0xFFFFFF), dark: hex(0x111111))
            : .white
    }

    static func glyph(for agent: String) -> String {
        AgentIdentity.glyph(agent)
    }

    // MARK: semantic (never reused as an accent)

    static let riskHigh = dynamic(light: hex(0xC7362F), dark: hex(0xFF6A52))
    static let riskMed  = dynamic(light: hex(0xB2721A), dark: hex(0xFFB43D))
    static let ok       = dynamic(light: hex(0x3F7A33), dark: hex(0x93A870))

    static func risk(_ level: Risk) -> Color {
        switch level {
        case .high:   return riskHigh
        case .medium: return riskMed
        case .low:    return muted
        }
    }

    static func riskLabel(_ level: Risk) -> String {
        switch level {
        case .high:   return "risk: high"
        case .medium: return "risk: medium"
        case .low:    return "risk: low"
        }
    }

    // MARK: shape & type

    static let radius: CGFloat = 16
    static let radiusSmall: CGFloat = 11

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: helpers

    private static func hex(_ value: UInt32) -> UIColor {
        UIColor(
            red:   CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue:  CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

// MARK: - reusable pieces

/// Small square agent badge — the same mark used in the prototypes.
struct AgentGlyph: View {
    let agent: String
    var size: CGFloat = 30

    var body: some View {
        if ProviderArtwork.isAvailable(agent) {
            ProviderArtworkImage(agent: agent, size: size)
        } else {
            Text(Theme.glyph(for: agent))
                .font(Theme.mono(size * 0.45, .black))
                .foregroundStyle(Theme.glyphInk(for: agent))
                .frame(width: size, height: size)
                .background(Theme.accent(for: agent),
                            in: RoundedRectangle(cornerRadius: size * 0.3,
                                                 style: .continuous))
        }
    }
}

/// Uppercase micro-label used for section headers and metadata.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.muted

    var body: some View {
        Text(L(text).uppercased())
            .font(.system(size: 10.5, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(L(text).uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// Card surface every block sits on.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// Primary / secondary buttons that match the prototype's weight.
struct FilledButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var tint: Color
    var textColor: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isEnabled ? textColor : Theme.disabledInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                isEnabled ? tint : Theme.disabledFill,
                in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
            )
            .opacity(configuration.isPressed && isEnabled ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
    }
}

struct OutlineButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var tint: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isEnabled ? tint : Theme.disabledInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .stroke(isEnabled ? tint.opacity(0.45) : Theme.disabledFill, lineWidth: 1.5)
            )
            .opacity(configuration.isPressed && isEnabled ? 0.6 : 1)
    }
}

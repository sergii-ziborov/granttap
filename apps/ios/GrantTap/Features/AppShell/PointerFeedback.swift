import SwiftUI

#if targetEnvironment(macCatalyst)
/// Appearance only: SwiftUI retains standard button activation and focus.
private struct PointerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var selected = false
    var cornerRadius: CGFloat = 9
    var feedbackColor: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(selected ? Theme.codex.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: cornerRadius))
            .pointerFeedback(cornerRadius: cornerRadius, isPressed: configuration.isPressed,
                             color: feedbackColor)
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.5)
    }
}
#endif

extension View {
    @ViewBuilder
    func pointerButtonStyle(selected: Bool = false, cornerRadius: CGFloat = 9,
                            feedbackColor: Color = Theme.ink) -> some View {
        #if targetEnvironment(macCatalyst)
        buttonStyle(PointerButtonStyle(selected: selected, cornerRadius: cornerRadius,
                                       feedbackColor: feedbackColor))
        #else
        buttonStyle(.plain)
        #endif
    }

    @ViewBuilder
    func pointerFeedback(cornerRadius: CGFloat = 9, isPressed: Bool = false,
                         color: Color = Theme.ink) -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(MacPointerFeedback(cornerRadius: cornerRadius, isPressed: isPressed, color: color))
        #else
        self
        #endif
    }
}

#if targetEnvironment(macCatalyst)
private struct MacPointerFeedback: ViewModifier {
    let cornerRadius: CGFloat
    let isPressed: Bool
    let color: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    private var shade: Double {
        guard isEnabled else { return 0 }
        return isPressed ? 0.16 : (hovered ? 0.10 : 0)
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .contentShape(shape)
            .overlay {
                shape.fill(color.opacity(shade)).allowsHitTesting(false)
            }
            .overlay {
                shape.stroke(color.opacity(isEnabled && hovered ? 0.20 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovered)
    }
}
#endif

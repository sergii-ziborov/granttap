import SwiftUI

struct ChatAccessoryPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
            .pointerFeedback(cornerRadius: 18, isPressed: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .frame(minHeight: 44)
    }
}

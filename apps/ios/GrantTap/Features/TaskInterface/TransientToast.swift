import SwiftUI

/// A short confirmation that something happened.
///
/// A control that only greys out after a tap says nothing about whether the
/// tap worked: the person is left reading the absence of a change. This says
/// it once, briefly, and gets out of the way.
struct TransientToast: ViewModifier {
    @Binding var message: String?
    /// Long enough to read a short sentence, short enough not to be dismissed.
    var seconds: Double = 2.5

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.raised, in: Capsule())
                    .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                    .padding(.bottom, 24)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                    .accessibilityIdentifier("toast")
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                        self.message = nil
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: message)
    }
}

extension View {
    func transientToast(_ message: Binding<String?>) -> some View {
        modifier(TransientToast(message: message))
    }
}

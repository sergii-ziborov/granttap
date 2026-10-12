import SwiftUI

extension TaskChatView {
    /// A reading shortcut floats above the transcript, just above the composer.
    func jumpToLatestButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            userMessageAnchor = nil
            requestJumpSettling = false
            pendingUserJump = false
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        }
        .pointerButtonStyle()
        .accessibilityLabel(L("Jump to latest messages"))
        .accessibilityIdentifier("chat.jumpToLatest")
        .padding(.trailing, 20)
    }
}

import SwiftUI

extension TaskChatView {
    /// Navigation stays in the pinned request strip, outside the scrolling surface.
    func jumpToLatestButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            userMessageAnchor = nil
            pendingUserJump = false
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Jump to latest messages"))
        .accessibilityIdentifier("chat.jumpToLatest")
        .padding(.trailing, 16)
    }
}

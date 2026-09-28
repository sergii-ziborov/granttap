import SwiftUI

extension TaskChatView {
    var latestUserEntry: ActivityEntry? {
        ChatPinnedUserMessage.entry(
            in: ChatActivityGrouping.rows(visibleTimeline),
            topRowId: topVisibleTranscriptRow
        )
    }

    func latestUserMessageButton(
        _ entry: ActivityEntry, proxy: ScrollViewProxy
    ) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(ChatScrollTarget.forEntry(entry), anchor: .center)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.message")
                Text(entry.text.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.surface.opacity(0.97))
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
        .accessibilityIdentifier("chat.latest-user-message")
    }
}

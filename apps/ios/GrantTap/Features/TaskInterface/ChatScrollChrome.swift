import SwiftUI

/// Which of this person's lines has left the top of the chat, and whether the
/// foot of the transcript is still on screen.
enum ChatScrollChrome {
    struct UserLine: Equatable {
        let scrollId: String
        let entryId: String
        let text: String
    }

    static func userLines(_ items: [CombinedTaskTimelineItem]) -> [UserLine] {
        items.compactMap { item in
            guard case .activity(let entry) = item, entry.kind == "user" else { return nil }
            let shown = ChatTranscriptText.display(entry.text)
            return UserLine(
                scrollId: item.id,
                entryId: entry.id,
                text: shown.isEmpty ? L("Attachment") : shown
            )
        }
    }

    /// The newest of this person's lines that has already crossed the top.
    /// A row the lazy stack has dropped is above once a later row is visible.
    static func pinned(
        users: [UserLine],
        minYById: [String: CGFloat],
        visibleIds: Set<String>,
        orderedIds: [String],
        top: CGFloat
    ) -> UserLine? {
        let firstVisibleIndex = orderedIds.firstIndex { visibleIds.contains($0) }
        return users.last { user in
            if let y = minYById[user.scrollId] { return y < top }
            guard let firstVisibleIndex,
                  let userIndex = orderedIds.firstIndex(of: user.scrollId) else { return false }
            return userIndex < firstVisibleIndex
        }
    }

    static func visibleIds(_ frames: [String: CGRect], viewportHeight: CGFloat) -> Set<String> {
        Set(frames.compactMap { id, frame in
            frame.maxY > 0 && frame.minY < viewportHeight ? id : nil
        })
    }

    static func showJumpToLatest(
        lastMaxY: CGFloat?,
        viewportHeight: CGFloat,
        slop: CGFloat = 72
    ) -> Bool {
        guard let lastMaxY, viewportHeight > 0 else { return false }
        return lastMaxY > viewportHeight + slop
    }
}

struct ChatRowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ChatViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatStickyUserBar: View {
    let text: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 11, weight: .bold))
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised.opacity(0.96))
            .overlay(Rectangle().fill(accent).frame(width: 3), alignment: .leading)
            .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Jump to this message"))
        .accessibilityIdentifier("chat.sticky-user")
    }
}

struct ChatJumpToLatestButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Theme.raised, in: Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.14), radius: 8, y: 3)
        }
        .accessibilityLabel(L("Jump to latest"))
        .accessibilityIdentifier("chat.jump-latest")
        .padding(.trailing, 14)
        .padding(.bottom, 12)
    }
}

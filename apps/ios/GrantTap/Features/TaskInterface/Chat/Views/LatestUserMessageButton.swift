import SwiftUI

extension TaskChatView {
    var latestUserEntry: ActivityEntry? {
        ChatPinnedUserMessage.entry(in: ChatActivityGrouping.rows(visibleTimeline),
            topRowId: chatIsAtBottom ? nil : topVisibleTranscriptRow)
    }

    var previousUserEntry: ActivityEntry? {
        if chatIsAtBottom || userMessageAnchor != nil {
            return TranscriptRequestBoundary.previous(in: rootEntries, before: userMessageAnchor)
        }
        return ChatPinnedUserMessage.navigationEntry(in: ChatActivityGrouping.rows(visibleTimeline),
            topRowId: topVisibleTranscriptRow, afterJump: userMessageAnchor)
    }

    func latestUserMessageButton(_ proxy: ScrollViewProxy) -> some View {
        Button { navigateToPreviousRequest(proxy) } label: {
            HStack(spacing: 7) {
                if historyLoading && previousUserEntry == nil {
                    ProgressView().controlSize(.small)
                } else { Image(systemName: "arrow.up.message") }
                Text(previousRequestTitle).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(historyLoading && previousUserEntry == nil)
        .background(Theme.surface.opacity(0.97))
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
        .accessibilityLabel(L("Previous user message") + ": " + previousRequestTitle)
        .accessibilityIdentifier("chat.latest-user-message")
    }

    private var previousRequestTitle: String {
        let first = transcriptHistory?.hasMore != true && !historyLoading && userMessageAnchor != nil
            ? rootEntries.first { $0.id == userMessageAnchor } : nil
        if let entry = previousUserEntry ?? first {
            let text = entry.text.replacingOccurrences(of: "\n", with: " ")
            return text.isEmpty ? L("Attachment") : text
        }
        if historyError { return L("Retry loading previous user message") }
        if transcriptHistory?.hasMore == true || !activitySnapshotKnown {
            return L("Loading previous user message…")
        }
        return userMessageAnchor == nil ? L("No user messages yet") : L("First user message")
    }

    func navigateToPreviousRequest(_ proxy: ScrollViewProxy) {
        guard let entry = previousUserEntry else {
            if transcriptHistory?.hasMore == true {
                pendingUserJump = true
                if historyError { retryOrLoadEarlierMessages(proxy) }
                else { loadEarlierMessages(proxy, automatic: true) }
            } else if let userMessageAnchor,
                      let first = rootEntries.first(where: { $0.id == userMessageAnchor }) {
                proxy.scrollTo(ChatScrollTarget.forEntry(first), anchor: .top)
            } else { retryTranscript() }
            return
        }
        pendingUserJump = false
        userMessageAnchor = entry.id
        requestJumpSettling = true
        chatIsAtBottom = transcriptFitsViewport
        let target = ChatScrollTarget.forEntry(entry)
        // Updating the pinned strip changes the scroll view's layout. Move on
        // the next layout pass, then repeat if history reconciliation moved it.
        DispatchQueue.main.async {
            guard userMessageAnchor == entry.id else { return }
            proxy.scrollTo(target, anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard userMessageAnchor == entry.id else { return }
                proxy.scrollTo(target, anchor: .top)
                ensurePreviousRequest(proxy)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if userMessageAnchor == entry.id { requestJumpSettling = false }
                }
            }
        }
    }

    func ensurePreviousRequest(_ proxy: ScrollViewProxy) {
        guard historyReadingActive, !historyLoading, !historyError,
              TranscriptRequestBoundary.needsEarlierPage(in: rootEntries,
                  before: userMessageAnchor ?? latestUserEntry?.id)
        else { return }
        loadEarlierMessages(proxy, automatic: true)
    }

    func updateTopTranscriptRow(_ top: String, proxy: ScrollViewProxy) {
        guard topVisibleTranscriptRow != top else { return }
        topVisibleTranscriptRow = top
        if !requestJumpSettling, !chatIsAtBottom, let anchor = userMessageAnchor,
           let request = latestUserEntry,
           let readingIndex = rootEntries.firstIndex(where: { $0.id == request.id }),
           let anchorIndex = rootEntries.firstIndex(where: { $0.id == anchor }), readingIndex < anchorIndex {
            userMessageAnchor = nil
            ensurePreviousRequest(proxy)
        }
    }
}

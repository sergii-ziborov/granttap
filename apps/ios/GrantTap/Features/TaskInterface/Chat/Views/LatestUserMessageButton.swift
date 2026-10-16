import SwiftUI

extension TaskChatView {
    var latestUserEntry: ActivityEntry? {
        requestNavigation.entry(
            topRowId: chatIsAtBottom ? nil : topVisibleTranscriptRow)
    }

    var previousUserEntry: ActivityEntry? {
        if chatIsAtBottom || userMessageAnchor != nil {
            let latest = requestIndex.previous(before: nil)
            let anchor = userMessageAnchor ?? (latestRequestIsVisibleAtTop ? latest?.id : nil)
            return requestIndex.previous(before: anchor)
                ?? (userMessageAnchor == nil ? latest : nil)
        }
        return requestNavigation.navigationEntry(
            topRowId: topVisibleTranscriptRow, afterJump: userMessageAnchor)
    }

    private var latestRequestIsVisibleAtTop: Bool {
        guard let topVisibleTranscriptRow,
              let request = requestNavigation.request(atRow: topVisibleTranscriptRow),
              let latest = requestIndex.previous(before: nil)
        else { return false }
        return request.id == latest.id
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
            .background(Theme.surface.opacity(0.97))
            .contentShape(Rectangle())
        }
        .pointerButtonStyle()
        .disabled(historyLoading && previousUserEntry == nil)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
        .accessibilityLabel(L("Previous user message") + ": " + previousRequestTitle)
        .accessibilityIdentifier("chat.latest-user-message")
    }

    private var previousRequestTitle: String {
        let first = transcriptHistory?.hasMore != true && !historyLoading && userMessageAnchor != nil
            ? userMessageAnchor.flatMap { requestIndex.request(containing: $0) } : nil
        if let entry = previousUserEntry ?? first {
            let text = entry.text.prefix(240).replacingOccurrences(of: "\n", with: " ")
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
                      let first = requestIndex.request(containing: userMessageAnchor) {
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
              requestIndex.needsEarlierPage(
                  before: userMessageAnchor ?? latestUserEntry?.id)
        else { return }
        loadEarlierMessages(proxy, automatic: true)
    }

    func updateTopTranscriptRow(_ top: String, proxy: ScrollViewProxy) {
        guard topVisibleTranscriptRow != top else { return }
        topVisibleTranscriptRow = top
        if !requestJumpSettling, !chatIsAtBottom, let anchor = userMessageAnchor,
           let request = latestUserEntry,
           let readingIndex = requestIndex.position(of: request.id),
           let anchorIndex = requestIndex.position(of: anchor), readingIndex < anchorIndex {
            userMessageAnchor = nil
            ensurePreviousRequest(proxy)
        }
    }
}

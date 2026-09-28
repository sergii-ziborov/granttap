import SwiftUI

struct ChatHistoryPositionKey: PreferenceKey {
    static var defaultValue: CGFloat? { nil }
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

extension TaskChatView {
    var transcriptHistory: TranscriptHistoryPage? { model.activities[chatSessionId]?.history }

    @ViewBuilder
    func olderMessagesHeader(_ proxy: ScrollViewProxy) -> some View {
        if transcriptHistory?.hasMore == true {
            HStack {
                if historyLoading { ProgressView().controlSize(.small) }
                if historyError {
                    Button(L("Retry loading earlier messages")) { retryOrLoadEarlierMessages(proxy) }
                        .accessibilityIdentifier("chat.history.more")
                }
                Spacer()
            }
            .font(.system(size: 13))
            .background(GeometryReader { geometry in
                Color.clear.preference(key: ChatHistoryPositionKey.self,
                    value: geometry.frame(in: .named("chat-transcript")).minY)
            })
        }
    }

    func retryOrLoadEarlierMessages(_ proxy: ScrollViewProxy) {
        guard historyError else { loadEarlierMessages(proxy); return }
        historyError = false
        pendingHistoryCursor = nil
        if var activity = model.activities[chatSessionId] {
            activity.history = nil
            model.activities[chatSessionId] = activity
        }
        retryTranscript()
    }

    func loadEarlierMessages(_ proxy: ScrollViewProxy, automatic: Bool = false) {
        guard !historyLoading, transcriptHistory?.hasMore == true,
              let cursor = transcriptHistory?.cursor else { return }
        historyLoading = true
        historyError = false
        historyPreservedBottom = automatic && userMessageAnchor == nil && focusEntryId == nil
        if !historyPreservedBottom { chatIsAtBottom = false }
        if historyPreservedBottom { historyScrollAnchor = "chat-bottom" }
        else if automatic, let id = userMessageAnchor,
                let request = rootEntries.first(where: { $0.id == id }) {
            historyScrollAnchor = ChatScrollTarget.forEntry(request)
        } else { historyScrollAnchor = topVisibleTranscriptRow }
        pendingHistoryCursor = cursor
        #if DEBUG
        if DemoTranscriptHistory.load(cursor: cursor, sessionId: chatSessionId, model: model) { return }
        #endif
        #if targetEnvironment(macCatalyst)
        if model.usesLocalMCP(for: currentSession) {
            Task {
                await loadLocalConversation(cursor: cursor)
                if localActivityError { historyLoading = false; historyError = true }
            }
        } else {
            model.relayForSession(chatSessionId)?.requestSessionEvents(
                sessionId: chatSessionId, history: true, historyCursor: cursor)
        }
        #else
        model.relayForSession(chatSessionId)?.requestSessionEvents(
            sessionId: chatSessionId, history: true, historyCursor: cursor)
        #endif
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if pendingHistoryCursor == cursor && historyLoading {
                historyLoading = false
                historyError = true
            }
        }
    }

    func historyArrived(_ proxy: ScrollViewProxy) {
        guard historyLoading, transcriptHistory?.requestedCursor == pendingHistoryCursor else { return }
        historyLoading = false
        // A provider returning the same cursor cannot advance. Keep a visible
        // retry instead of continuously requesting the same page.
        historyError = transcriptHistory?.hasMore == true
            && transcriptHistory?.cursor == pendingHistoryCursor
        pendingHistoryCursor = nil
        if let anchor = historyScrollAnchor {
            let edge: UnitPoint = historyPreservedBottom ? .bottom : .top
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let id = userMessageAnchor, let request = rootEntries.first(where: { $0.id == id }) {
                    proxy.scrollTo(ChatScrollTarget.forEntry(request), anchor: .top)
                } else { proxy.scrollTo(anchor, anchor: edge) }
                if pendingUserJump && previousUserEntry != nil { navigateToPreviousRequest(proxy) }
                ensurePreviousRequest(proxy)
            }
        } else if pendingUserJump && previousUserEntry != nil {
            navigateToPreviousRequest(proxy)
        }
        historyScrollAnchor = nil
    }
}

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
                Button(historyError ? L("Retry loading earlier messages") : L("Show earlier messages")) {
                    loadEarlierMessages(proxy)
                }
                .disabled(historyLoading)
                .accessibilityIdentifier("chat.history.more")
                Spacer()
            }
            .font(.system(size: 13))
            .background(GeometryReader { geometry in
                Color.clear.preference(key: ChatHistoryPositionKey.self,
                    value: geometry.frame(in: .named("chat-transcript")).minY)
            })
        }
    }

    func loadEarlierMessages(_ proxy: ScrollViewProxy) {
        guard !historyLoading, transcriptHistory?.hasMore == true,
              let cursor = transcriptHistory?.cursor else { return }
        historyLoading = true
        historyError = false
        chatIsAtBottom = false
        historyScrollAnchor = topVisibleTranscriptRow
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
        historyError = false
        pendingHistoryCursor = nil
        if let anchor = historyScrollAnchor {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { proxy.scrollTo(anchor, anchor: .top) }
        }
        historyScrollAnchor = nil
    }
}

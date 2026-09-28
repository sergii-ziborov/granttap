import Foundation

struct HistoryPagingState {
    var sessions: [SessionInfo] = []
    var cursor: String?
    var hasMore = true
    var sourceLimited = false
    var pendingRequestId: String?
    var error: String?
}

extension AppModel {
    var taskHistoryPageState: HistoryPagingState {
        let room = connectionRegistry.preferredId ?? relay?.pairing.room ?? ""
        return historyPagingByRoom[room] ?? HistoryPagingState()
    }

    func loadMoreTaskHistoryIfNeeded() {
        guard !demoMode,
              let room = connectionRegistry.preferredId ?? relay?.pairing.room,
              let client = relaysByRoom[room] ?? relay,
              client.pairing.room == room else { return }
        var state = historyPagingByRoom[room] ?? HistoryPagingState()
        guard state.hasMore, state.pendingRequestId == nil else { return }
        let requestId = UUID().uuidString.lowercased()
        state.pendingRequestId = requestId
        state.error = nil
        historyPagingByRoom[room] = state
        client.requestSessionsHistoryPage(requestId: requestId, cursor: state.cursor) { [weak self] error in
            guard let self, error != nil,
                  var current = self.historyPagingByRoom[room],
                  current.pendingRequestId == requestId else { return }
            current.pendingRequestId = nil
            current.error = L("History request could not be sent.")
            self.historyPagingByRoom[room] = current
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self, var current = self.historyPagingByRoom[room],
                  current.pendingRequestId == requestId else { return }
            current.pendingRequestId = nil
            current.error = L("History request timed out.")
            self.historyPagingByRoom[room] = current
        }
    }

    func receiveSessionsHistoryPage(_ page: SessionsHistoryPage, fromRoom room: String) {
        guard room == (connectionRegistry.preferredId ?? relay?.pairing.room),
              var state = historyPagingByRoom[room],
              state.pendingRequestId == page.requestId else { return }
        state.pendingRequestId = nil
        if page.resetRequired == true {
            state = HistoryPagingState()
            state.error = L("History changed. Reload to continue.")
        } else {
            state.sessions = Self.deduplicatedSessions(state.sessions + page.sessions)
            state.cursor = page.nextCursor
            state.hasMore = page.hasMore
            state.sourceLimited = page.sourceLimited == true
            state.error = nil
        }
        historyPagingByRoom[room] = state
    }
}

import SwiftUI

struct CapabilityChatDestination: View {
    let target: CapabilityChatTarget
    let createdAt: Double
    var focusEntryId: String? = nil
    @EnvironmentObject private var model: AppModel
    @State private var prepared = false
    @State private var rejected = false

    private var session: SessionInfo {
        let resolved = model.resolvedSessionId(target.sessionId)
        return model.sessions.first { $0.sessionId == resolved }
            ?? model.sessionHistory.first { $0.sessionId == resolved }
            ?? model.archivedSessions[resolved]
            ?? model.sessions.first { $0.sessionId == target.sessionId }
            ?? model.sessionHistory.first { $0.sessionId == target.sessionId }
            ?? model.archivedSessions[target.sessionId]
            ?? SessionInfo(
                sessionId: target.sessionId,
                agent: "unknown",
                title: L("Loading chat history…"),
                state: "idle",
                startedAt: createdAt,
                lastActivityAt: createdAt,
                tokensSession: 0,
                tokensLastTurn: 0
            )
    }

    var body: some View {
        Group {
            if rejected {
                CompatEmptyState(
                    title: L("Chat unavailable"),
                    systemImage: "exclamationmark.bubble",
                    description: L("The source computer was removed or this chat id is ambiguous across computers.")
                )
            } else if prepared {
                TaskChatView(session: session, focusEntryId: focusEntryId)
                    .environmentObject(model)
            } else {
                ProgressView(L("Loading encrypted chat…"))
            }
        }
        .onAppear(perform: prepare)
    }

    private func prepare() {
        guard !prepared, !rejected,
              model.connectionRegistry.connections.contains(where: { $0.id == target.roomId })
        else { return }
        switch model.sessionRoomOwnership(forSessionId: target.sessionId) {
        case .unknown:
            model.rememberSessionSourceRoom(target.roomId, sessionId: target.sessionId)
            prepared = true
        case .exact(let owner) where owner == target.roomId:
            prepared = true
        default:
            rejected = true
        }
    }
}

/// Stable push id — never bind destination to Equatable `SessionInfo`.
struct HistoryOpenSession: Identifiable, Hashable {
    let id: String
}

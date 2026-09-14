import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

extension ContentView {
    var chatNavigationActive: Binding<Bool> {
        Binding(
            get: { openedSession != nil },
            set: { if !$0 { openedSession = nil } }
        )
    }

    @ViewBuilder
    var openedSessionDestination: some View {
        if let item = openedSession,
           let session = model.sessions.first(where: { $0.sessionId == item.id })
            ?? model.sessionHistory.first(where: { $0.sessionId == item.id })
            ?? model.archivedSessions[item.id] {
            SessionRouteDestination(session: session).environmentObject(model)
                .onDisappear {
                    if model.sessionToOpen == item.id { model.sessionToOpen = nil }
                }
        } else {
            // Keep destination identity while catalog flickers — never auto-clear.
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
        }
    }

    /// The alert lives off an optional so a second link cannot queue up behind
    /// the first; dismissing always drops the staged pairing.
    var pairingPrompt: Binding<Bool> {
        Binding(
            get: { pendingPairing != nil },
            set: { if !$0 { pendingPairing = nil } }
        )
    }

    var pairingErrorPrompt: Binding<Bool> {
        Binding(
            get: { pairingLinkError != nil },
            set: { if !$0 { pairingLinkError = nil } }
        )
    }

    func fetchPairing(_ link: Pairing.SecureLink) {
        Task {
            let result = await securePairingFetcher(link)
            await MainActor.run {
                switch result {
                case .success(let pairing):
                    showPairing = false
                    showSettings = false
                    openedSession = nil
                    pendingPairing = pairing
                case .failure(let error):
                    pairingLinkError = error.message
                }
            }
        }
    }

    #if DEBUG
    /// Auto-open first demo chat only after launch chrome clears (avoids MainActor jank).
    func autoOpenDebugSessionIfNeeded(from sessions: [SessionInfo]) {
        guard ProcessInfo.processInfo.environment["GRANTTAP_OPEN_SESSION"] != nil,
              openedSession == nil,
              !security.launching,
              let first = sessions.first else { return }
        openedSession = OpenSession(id: first.sessionId)
    }
    #endif

    func openRequestedSession(from sessions: [SessionInfo]) {
        guard let sessionId = model.sessionToOpen else { return }
        let pool = sessions + model.sessionHistory + Array(model.archivedSessions.values)
        guard pool.contains(where: { $0.sessionId == sessionId }) else { return }
        // Sheets sit above SecurityLockView — never present chat content while locked / PIN setup.
        if security.showsLockUI { return }
        if security.launching { return }
        // Already showing this chat — noop. Never rebind sheet identity on
        // sessions.status churn (was SessionInfo Equatable + sheet(item:)).
        if openedSession?.id == sessionId {
            model.sessionToOpen = nil
            return
        }
        // Another chat is open — do not hijack navigation on inbound Mac updates.
        if let openId = openedSession?.id,
           sessions.contains(where: { $0.sessionId == openId })
            || model.sessionHistory.contains(where: { $0.sessionId == openId })
            || model.archivedSessions[openId] != nil {
            model.sessionToOpen = nil
            return
        }
        openedSession = OpenSession(id: sessionId)
        model.sessionToOpen = nil
    }

    /// Host only — a full relay URL with base64 query junk is unreadable in an
    /// alert, and the host is what the user has to judge.
    static func relayHost(_ relayUrl: String) -> String {
        URLComponents(string: relayUrl)?.host ?? relayUrl
    }

    // MARK: header
}

private struct SessionRouteDestination: View {
    let session: SessionInfo

    var body: some View {
        TaskChatView(session: session)
    }
}

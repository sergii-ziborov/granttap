import SwiftUI

extension ContentView {
    func prepareNewTask() {
        composeSessionId = nil
        replyRequestId = nil
        composeAgent = TaskComposerRoutePresentation.defaultProvider(
            saved: savedComposeAgent, sessions: model.sessions,
            enabledProviders: model.agentMeshPreferences.enabledProviders
        )
        showNewTask = true
        DispatchQueue.main.async { composeFocused = true }
    }

    func handlePairingURL(_ url: URL) {
        if let pairing = Pairing.fromURI(url.absoluteString) {
            showPairing = false
            showSettings = false
            openedSession = nil
            pendingPairing = pairing
        } else if let link = Pairing.secureLink(fromURI: url.absoluteString) {
            fetchPairing(link)
        }
    }
}

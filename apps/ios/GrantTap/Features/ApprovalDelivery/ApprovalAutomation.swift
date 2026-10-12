import Foundation

@MainActor
extension AppModel {
    func setSessionAutoAccept(_ sessionId: String, _ level: String, authorizeProjectAsk: Bool = false,
                              expectedPolicyRevision: Int? = nil, approvalRequestId: String? = nil) {
        guard Self.autoAcceptLevels.contains(level) else { return }
        guard let sessionRelay = relayForSession(sessionId) else {
            append("auto-accept blocked: ambiguous source room")
            return
        }
        automationPrevious[sessionId] = autoAcceptBySession[sessionId] ?? ""
        automationDesired[sessionId] = level
        automationErrors.removeValue(forKey: sessionId)
        autoAcceptBySession[sessionId] = level
        // Setting a per-chat level implies GrantTap should gate this chat.
        if excludedSessions.contains(sessionId) {
            excludedSessions.removeAll { $0 == sessionId }
            sessionRelay.sendConfig(includeSession: sessionId)
        }
        let operation = sessionRelay.sendConfig(autoAcceptSessionId: sessionId,
            autoAcceptSessionLevel: level, authorizeProjectAsk: authorizeProjectAsk,
            expectedPolicyRevision: expectedPolicyRevision, approvalRequestId: approvalRequestId)
        automationPending[sessionId] = operation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, self.automationPending[sessionId] == operation else { return }
            self.failAutomation(sessionId, message: L("The computer has not confirmed this rule. Try again when it is online."))
        }
        AuditStore.shared.record("auto-accept", detail: "Chat auto-accept set to \(level)")
    }

    func clearSessionAutoAccept(_ sessionId: String) {
        guard let sessionRelay = relayForSession(sessionId) else {
            append("auto-accept clear blocked: ambiguous source room")
            return
        }
        autoAcceptBySession.removeValue(forKey: sessionId)
        sessionRelay.sendConfig(autoAcceptSessionId: sessionId, clearAutoAcceptSession: true)
        AuditStore.shared.record("auto-accept", detail: "Chat auto-accept cleared (uses default)")
    }

    func setAutoAcceptPaused(_ paused: Bool) {
        autoAcceptPaused = paused
        relay?.sendConfig(autoAcceptPaused: paused)
        AuditStore.shared.record("auto-accept", detail: paused ? "Auto-accept paused" : "Auto-accept resumed")
    }

    static let autoAcceptLevels = ["ask", "safe", "except_push", "except_destructive", "full"]

    func attachAutomationReceipts(_ client: RelayClient, room: String) {
        client.onConfigCommandResult = { [weak self] result in
            self?.receiveAutomationResult(result, fromRoom: room)
        }
    }

    func receiveAutomationResult(_ result: ConfigCommandResult, fromRoom room: String) {
        guard let id = result.sessionId, automationPending[id] == result.operationId,
              sessionSourceRooms[id] == [room] else { return }
        if result.ok, let level = result.level, Self.autoAcceptLevels.contains(level) {
            if let wanted = automationDesired[id], wanted != level {
                failAutomation(id, message: L("The computer's rules require a decision for this chat. Automation was not enabled."))
                autoAcceptBySession[id] = level
                return
            }
            autoAcceptBySession[id] = level
            automationPending.removeValue(forKey: id)
            automationPrevious.removeValue(forKey: id)
            automationDesired.removeValue(forKey: id)
        } else {
            failAutomation(id, message: L("The computer did not apply this rule. Refresh the connection and try again."))
        }
    }

    func failAutomation(_ id: String, message: String) {
        if let previous = automationPrevious.removeValue(forKey: id) {
            autoAcceptBySession[id] = previous.isEmpty ? nil : previous
        }
        automationPending.removeValue(forKey: id)
        automationDesired.removeValue(forKey: id)
        automationErrors[id] = message
    }
}

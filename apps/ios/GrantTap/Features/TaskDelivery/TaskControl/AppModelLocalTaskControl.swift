import Foundation

@MainActor
extension AppModel {
    func localTaskControlsAvailable(_ sessionId: String) -> Bool {
        #if targetEnvironment(macCatalyst)
        guard localMCPReader?.status?.taskControlsAvailable == true,
              let session = knownSession(for: sessionId, preferredAgent: nil) else { return false }
        return usesLocalTaskDelivery(for: session)
        #else
        return false
        #endif
    }

    @discardableResult
    func sendLocalTaskControl(_ sessionId: String, action: String, continue shouldContinue: Bool,
                              requestId: UUID? = nil) -> Bool {
        #if targetEnvironment(macCatalyst)
        guard localTaskControlsAvailable(sessionId), let session = knownSession(for: sessionId, preferredAgent: nil) else { return false }
        Task { @MainActor in
            do {
                let data = try await MacLocalTaskCommands.control(session, action: action, continue: shouldContinue)
                if action == "compact" {
                    let result = try JSONDecoder().decode(SessionCompactResult.self, from: data)
                    compactingSessions.remove(sessionId)
                    compactResults[sessionId] = result
                    append(result.message)
                } else if sessionControlRequestIds[sessionId] == requestId {
                    receive(try JSONDecoder().decode(SessionControlResult.self, from: data))
                }
            } catch {
                let message = L("Could not send to this Task. Retry after checking the Mac connection.")
                if action == "compact" {
                    compactingSessions.remove(sessionId)
                    compactResults[sessionId] = SessionCompactResult(type: "session.compact.result",
                        sessionId: sessionId, ok: false, message: message, createdAt: Date().timeIntervalSince1970 * 1_000)
                } else if sessionControlRequestIds[sessionId] == requestId {
                    receive(SessionControlResult(type: "session.control.result", sessionId: sessionId,
                        action: action, ok: false, message: message, createdAt: Date().timeIntervalSince1970 * 1_000))
                }
            }
            await refreshLocalTaskPreferences(sessionId)
        }
        return true
        #else
        return false
        #endif
    }

    @discardableResult
    func sendLocalTaskPreferences(_ sessionId: String, changes: [String: Any]) -> Bool {
        #if targetEnvironment(macCatalyst)
        guard localTaskControlsAvailable(sessionId), let session = knownSession(for: sessionId, preferredAgent: nil) else { return false }
        guard automationPending[sessionId] == nil else { return true }
        let operation = UUID().uuidString
        automationPending[sessionId] = operation
        automationErrors.removeValue(forKey: sessionId)
        Task { @MainActor in
            do {
                let result = try await MacLocalTaskCommands.preferences(session, changes: changes)
                guard automationPending[sessionId] == operation else { return }
                automationPending.removeValue(forKey: sessionId)
                guard result.accepted else {
                    automationErrors[sessionId] = L(result.error ?? "The computer did not apply this rule. Refresh the connection and try again.")
                    return
                }
                applyLocalTaskPreferences(result, sessionId: sessionId)
                if let desired = changes["auto_accept_level"] as? String, desired != result.level {
                    automationErrors[sessionId] = L("The computer's rules require a decision for this chat. Automation was not enabled.")
                }
                AuditStore.shared.record("session", detail: "Local chat settings confirmed by computer")
            } catch {
                guard automationPending[sessionId] == operation else { return }
                automationPending.removeValue(forKey: sessionId)
                automationErrors[sessionId] = L("The computer did not apply this rule. Refresh the connection and try again.")
            }
        }
        return true
        #else
        return false
        #endif
    }

    #if targetEnvironment(macCatalyst)
    func refreshLocalTaskPreferences(_ sessionId: String) async {
        guard !demoMode, automationPending[sessionId] == nil, !sessionControlPending.contains(sessionId),
              localTaskControlsAvailable(sessionId), let session = knownSession(for: sessionId, preferredAgent: nil),
              let result = try? await MacLocalTaskCommands.preferences(session), result.accepted,
              automationPending[sessionId] == nil, !sessionControlPending.contains(sessionId) else { return }
        applyLocalTaskPreferences(result, sessionId: sessionId)
    }

    func applyLocalTaskPreferences(_ result: MacTaskPreferences, sessionId: String) {
        guard result.accepted, result.session_id == sessionId else { return }
        if let latest = localMCPReader?.taskPreferences[sessionId]?.generated_at,
           let incoming = result.generated_at, incoming < latest { return }
        localMCPReader?.taskPreferences[sessionId] = result
        if autoAcceptBySession[sessionId] != result.level { autoAcceptBySession[sessionId] = result.level }
        if result.excluded == true {
            if !excludedSessions.contains(sessionId) { excludedSessions.append(sessionId) }
        } else if excludedSessions.contains(sessionId) { excludedSessions.removeAll { $0 == sessionId } }
        if let session = knownSession(for: sessionId, preferredAgent: nil), result.applying(to: session) != session {
            mutateSession(sessionId) { session in session = result.applying(to: session) }
        }
    }
    #endif
}

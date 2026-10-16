import Foundation

@MainActor
extension AppModel {
    /// Hold a chat: its computer refuses every tool call until it is resumed,
    /// and stops the turn it is running for it. The hold is applied on the
    /// phone at once so the screen answers the tap; the computer confirms.
    func pauseSession(_ sessionId: String) {
        controlSession(sessionId, action: "pause", continue: false)
    }

    /// Lift the hold and ask the agent to carry on where it stopped.
    func resumeSession(_ sessionId: String, continue shouldContinue: Bool = true) {
        controlSession(sessionId, action: "resume", continue: shouldContinue)
    }

    private func controlSession(_ sessionId: String, action: String, continue shouldContinue: Bool) {
        guard !sessionControlPending.contains(sessionId) else { return }
        let sessionRelay = relayForSession(sessionId)
        guard sessionRelay != nil || localTaskControlsAvailable(sessionId) else {
            append("\(action) blocked: ambiguous source room")
            return
        }
        let requestId = UUID()
        let deadline = Date().addingTimeInterval(Double(Self.sessionControlTimeout) / 1_000_000_000)
        sessionControlRequestIds[sessionId] = requestId
        sessionControlResults.removeValue(forKey: sessionId)
        sessionControlPending.insert(sessionId)
        // The screen answers the tap, but what it shows is still a guess until
        // the computer says so, so what it showed before is kept to go back to.
        sessionControlPrevious[sessionId] = pausedState(sessionId)
        mutateSession(sessionId) { session in session.paused = action == "pause" }
        if !sendLocalTaskControl(sessionId, action: action, continue: shouldContinue, requestId: requestId) {
            sessionRelay?.controlSession(sessionId, action: action, continue: shouldContinue)
        }
        AuditStore.shared.record("session", detail: "\(action) requested for chat")
        // A computer that never answers must not leave the chat stuck between
        // states: the guess is taken back, and the next tap sends it again.
        Task { @MainActor [weak self] in
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
            guard let self, self.sessionControlPending.contains(sessionId),
                  self.sessionControlRequestIds[sessionId] == requestId else { return }
            self.sessionControlRequestIds.removeValue(forKey: sessionId)
            self.sessionControlPending.remove(sessionId)
            self.restoreSessionControlGuess(sessionId)
            self.sessionControlResults[sessionId] = SessionControlResult(
                type: "session.control.result", sessionId: sessionId, action: action, ok: false,
                message: L("No answer from the computer: the chat is as it was."),
                createdAt: Date().timeIntervalSince1970 * 1_000
            )
            self.append("\(action): no answer from the computer yet")
        }
    }

    static var sessionControlTimeout: UInt64 = 20_000_000_000

    /// What the phone last had reason to believe about a chat's hold.
    private func pausedState(_ sessionId: String) -> Bool {
        if let session = sessions.first(where: { $0.sessionId == sessionId }) { return session.isPaused }
        if let session = sessionHistory.first(where: { $0.sessionId == sessionId }) { return session.isPaused }
        return archivedSessions[sessionId]?.isPaused ?? false
    }

    /// Put back what the phone showed before it guessed.
    private func restoreSessionControlGuess(_ sessionId: String) {
        guard let previous = sessionControlPrevious.removeValue(forKey: sessionId) else { return }
        mutateSession(sessionId) { session in session.paused = previous }
    }

    /// The computer's word on a pause or resume, replacing the phone's guess.
    ///
    /// A refusal is not a hold: what the computer would not do, the phone does
    /// not show as done. A pause a member asked for is answered to that member.
    func receive(_ result: SessionControlResult) {
        sessionControlRequestIds.removeValue(forKey: result.sessionId)
        sessionControlPending.remove(result.sessionId)
        sessionControlResults[result.sessionId] = result
        if result.ok {
            sessionControlPrevious.removeValue(forKey: result.sessionId)
            mutateSession(result.sessionId) { session in session.paused = result.action == "pause" }
        } else {
            restoreSessionControlGuess(result.sessionId)
        }
        handOffControlResultToMember(result)
        append(result.message)
    }

    func compactSession(_ sessionId: String) {
        guard !compactingSessions.contains(sessionId) else { return }
        let sessionRelay = relayForSession(sessionId)
        guard sessionRelay != nil || localTaskControlsAvailable(sessionId) else {
            append("compaction blocked: ambiguous source room")
            return
        }
        compactResults.removeValue(forKey: sessionId)
        compactingSessions.insert(sessionId)
        if !sendLocalTaskControl(sessionId, action: "compact", continue: false) { sessionRelay?.compactSession(sessionId) }
        AuditStore.shared.record("context", detail: "Codex compaction requested")
    }
}

import Foundation

@MainActor
extension AppModel {
    // Config controls — optimistic local update, machine confirms via next status.
    func setGating(_ on: Bool) {
        gatingEnabled = on
        relay?.sendConfig(enabled: on)
        append("gating: \(on ? "on" : "OFF")")
        AuditStore.shared.record("gating", detail: on ? "Remote approval enabled" : "Remote approval paused")
    }

    func setSessionExcluded(_ sessionId: String, _ excluded: Bool) {
        guard let sessionRelay = relayForSession(sessionId) else {
            append("session control blocked: ambiguous source room")
            return
        }
        if excluded {
            if !excludedSessions.contains(sessionId) { excludedSessions.append(sessionId) }
            sessionRelay.sendConfig(excludeSession: sessionId)
        } else {
            excludedSessions.removeAll { $0 == sessionId }
            sessionRelay.sendConfig(includeSession: sessionId)
        }
        AuditStore.shared.record("session", detail: excluded ? "Normal approval flow selected" : "GrantTap approval flow selected")
    }

    func isExcluded(_ sessionId: String) -> Bool { excludedSessions.contains(sessionId) }

    func autoAcceptLevel(for sessionId: String, projectId: String? = nil) -> String {
        AutoAcceptPresentation.resolved(
            paused: autoAcceptPaused,
            session: autoAcceptBySession[sessionId],
            project: projectId.flatMap { autoAcceptByProject[$0] },
            machine: autoAcceptDefault
        ).rawValue
    }

    func autoAcceptLevel(for session: SessionInfo) -> String {
        autoAcceptLevel(for: session.sessionId, projectId: session.projectId)
    }

    func setAutoAcceptDefault(_ level: String) {
        guard Self.autoAcceptLevels.contains(level) else { return }
        autoAcceptDefault = level
        relay?.sendConfig(autoAcceptDefault: level)
        AuditStore.shared.record("auto-accept", detail: "Default auto-accept set to \(level)")
    }

    func setSessionAutoAccept(_ sessionId: String, _ level: String) {
        guard Self.autoAcceptLevels.contains(level) else { return }
        guard let sessionRelay = relayForSession(sessionId) else {
            append("auto-accept blocked: ambiguous source room")
            return
        }
        autoAcceptBySession[sessionId] = level
        // Setting a per-chat level implies GrantTap should gate this chat.
        if excludedSessions.contains(sessionId) {
            excludedSessions.removeAll { $0 == sessionId }
            sessionRelay.sendConfig(includeSession: sessionId)
        }
        sessionRelay.sendConfig(autoAcceptSessionId: sessionId, autoAcceptSessionLevel: level)
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

    func setProjectAutoAccept(_ projectId: String, _ level: String?) {
        if let level {
            guard Self.autoAcceptLevels.contains(level) else { return }
            autoAcceptByProject[projectId] = level
            if !gatingEnabled { setGating(true) }
            setAutoAcceptPaused(false)
            relay?.sendConfig(autoAcceptProjectId: projectId, autoAcceptProjectLevel: level)
            AuditStore.shared.record("auto-accept", detail: "Project auto-accept set to \(level)")
        } else {
            autoAcceptByProject.removeValue(forKey: projectId)
            relay?.sendConfig(autoAcceptProjectId: projectId, clearAutoAcceptProject: true)
            AuditStore.shared.record("auto-accept", detail: "Project auto-accept cleared (uses computer default)")
        }
    }

    static let autoAcceptLevels = ["ask", "safe", "except_push", "except_destructive", "full"]

    func setSessionAccess(_ sessionId: String, _ accessLevel: String) {
        guard ["read-only", "workspace", "full"].contains(accessLevel) else { return }
        guard let sessionRelay = relayForSession(sessionId) else {
            append("access change blocked: ambiguous source room")
            return
        }
        if let index = sessions.firstIndex(where: { $0.sessionId == sessionId }) {
            sessions[index].accessLevel = accessLevel
        }
        sessionRelay.sendSessionAccess(sessionId: sessionId, accessLevel: accessLevel)
        AuditStore.shared.record("access", detail: "Task access set to \(accessLevel)")
    }

    func setSessionMcpAllowed(_ sessionId: String, serverName: String, allowed: Bool) {
        guard let sessionRelay = relayForSession(sessionId) else {
            append("MCP change blocked: ambiguous source room")
            return
        }
        mutateSession(sessionId) { session in
            var servers = session.mcpServers ?? []
            if let serverIndex = servers.firstIndex(where: { $0.name == serverName }) {
                servers[serverIndex].allowed = allowed
                session.mcpServers = servers
            }
        }
        sessionRelay.sendSessionMcp(sessionId: sessionId, serverName: serverName, allowed: allowed)
        AuditStore.shared.record("mcp", detail: "\(serverName) \(allowed ? "allowed" : "blocked") for task")
    }

    func setSessionSkillAllowed(_ sessionId: String, skillName: String, allowed: Bool) {
        guard let sessionRelay = relayForSession(sessionId) else {
            append("skill change blocked: ambiguous source room")
            return
        }
        mutateSession(sessionId) { session in
            var skills = session.skills ?? []
            if let idx = skills.firstIndex(where: { $0.name == skillName }) {
                skills[idx].allowed = allowed
            } else {
                skills.append(SkillInfo(name: skillName, allowed: allowed))
            }
            session.skills = skills
        }
        sessionRelay.sendSessionSkill(sessionId: sessionId, skillName: skillName, allowed: allowed)
        AuditStore.shared.record("skill", detail: "\(skillName) \(allowed ? "allowed" : "blocked") for task")
    }

    func setSessionShellAllowed(_ sessionId: String, allowed: Bool) {
        guard let sessionRelay = relayForSession(sessionId) else {
            append("shell change blocked: ambiguous source room")
            return
        }
        mutateSession(sessionId) { session in
            session.shellAllowed = allowed
        }
        sessionRelay.sendSessionShell(sessionId: sessionId, allowed: allowed)
        AuditStore.shared.record("shell", detail: "shell \(allowed ? "allowed" : "blocked") for task")
    }

    func setGlobalMcpAllowed(_ serverName: String, allowed: Bool) {
        guard connected, let relay else {
            append("global MCP change blocked: computer offline")
            return
        }
        if allowed { globalMcpDisabled.remove(serverName) }
        else { globalMcpDisabled.insert(serverName) }
        relay.sendGlobalMcp(serverName: serverName, allowed: allowed)
        AuditStore.shared.record("mcp", detail: "\(serverName) \(allowed ? "allowed" : "blocked") globally")
    }

    func setGlobalMcpAllowed(_ serverName: String, allowed: Bool, roomId: String) {
        guard let client = onlineRelay(forRoom: roomId) else {
            append("global MCP change blocked: computer offline")
            return
        }
        CapabilityCatalogStore.shared.setAllowed(allowed, kind: .mcp,
                                                  name: serverName, roomId: roomId)
        client.sendGlobalMcp(serverName: serverName, allowed: allowed)
        AuditStore.shared.record("mcp", detail: "\(serverName) \(allowed ? "allowed" : "blocked") globally")
    }

    func setGlobalSkillAllowed(_ skillName: String, allowed: Bool) {
        guard connected, let relay else {
            append("global skill change blocked: computer offline")
            return
        }
        if allowed { globalSkillsDisabled.remove(skillName) }
        else { globalSkillsDisabled.insert(skillName) }
        relay.sendGlobalSkill(skillName: skillName, allowed: allowed)
        AuditStore.shared.record("skill", detail: "\(skillName) \(allowed ? "allowed" : "blocked") globally")
    }

    func setGlobalSkillAllowed(_ skillName: String, allowed: Bool, roomId: String) {
        guard let client = onlineRelay(forRoom: roomId) else {
            append("global skill change blocked: computer offline")
            return
        }
        CapabilityCatalogStore.shared.setAllowed(allowed, kind: .skill,
                                                  name: skillName, roomId: roomId)
        client.sendGlobalSkill(skillName: skillName, allowed: allowed)
        AuditStore.shared.record("skill", detail: "\(skillName) \(allowed ? "allowed" : "blocked") globally")
    }

    private func onlineRelay(forRoom roomId: String) -> RelayClient? {
        guard let connection = connectionRegistry.connections.first(where: { $0.id == roomId }),
              snapshotForConnection(connection).phase == .live else { return nil }
        return relaysByRoom[roomId]
    }

    func setGlobalShellAllowed(_ allowed: Bool) {
        guard connected, let relay else {
            append("global CLI change blocked: computer offline")
            return
        }
        globalShellDisabled = !allowed
        relay.sendGlobalShell(allowed: allowed)
        AuditStore.shared.record("shell", detail: "CLI \(allowed ? "allowed" : "blocked") globally")
    }

    /// Update a session whether it lives in Active, History, or Archive.
    private func mutateSession(_ sessionId: String, _ body: (inout SessionInfo) -> Void) {
        if let i = sessions.firstIndex(where: { $0.sessionId == sessionId }) {
            body(&sessions[i])
            return
        }
        if let i = sessionHistory.firstIndex(where: { $0.sessionId == sessionId }) {
            body(&sessionHistory[i])
            return
        }
        if var archived = archivedSessions[sessionId] {
            body(&archived)
            archivedSessions[sessionId] = archived
        }
    }

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
        guard let sessionRelay = relayForSession(sessionId) else {
            append("\(action) blocked: ambiguous source room")
            return
        }
        sessionControlResults.removeValue(forKey: sessionId)
        sessionControlPending.insert(sessionId)
        // The screen answers the tap, but what it shows is still a guess until
        // the computer says so, so what it showed before is kept to go back to.
        sessionControlPrevious[sessionId] = pausedState(sessionId)
        mutateSession(sessionId) { session in session.paused = action == "pause" }
        sessionRelay.controlSession(sessionId, action: action, continue: shouldContinue)
        AuditStore.shared.record("session", detail: "\(action) requested for chat")
        // A computer that never answers must not leave the chat stuck between
        // states: the guess is taken back, and the next tap sends it again.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.sessionControlTimeout)
            guard let self, self.sessionControlPending.contains(sessionId) else { return }
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
        guard let sessionRelay = relayForSession(sessionId) else {
            append("compaction blocked: ambiguous source room")
            return
        }
        compactResults.removeValue(forKey: sessionId)
        compactingSessions.insert(sessionId)
        sessionRelay.compactSession(sessionId)
        AuditStore.shared.record("context", detail: "Codex compaction requested")
    }
}

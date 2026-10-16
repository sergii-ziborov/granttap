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
        if sendLocalTaskPreferences(sessionId, changes: ["excluded": excluded]) { return }
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

    func autoAcceptLevel(for sessionId: String) -> String {
        if autoAcceptPaused { return "ask" }
        if let project = (sessions + sessionHistory).first(where: {
            $0.sessionId == sessionId || $0.childThreads?.contains(where: { $0.threadId == sessionId }) == true
        })?.projectId {
            return autoAcceptBySession[sessionId] ?? autoAcceptByProject[project] ?? "ask"
        }
        return autoAcceptBySession[sessionId] ?? autoAcceptDefault
    }

    func setAutoAcceptDefault(_ level: String) {
        guard Self.autoAcceptLevels.contains(level) else { return }
        autoAcceptDefault = level
        relay?.sendConfig(autoAcceptDefault: level)
        AuditStore.shared.record("auto-accept", detail: "Default auto-accept set to \(level)")
    }

    func setSessionAccess(_ sessionId: String, _ accessLevel: String) {
        guard ["read-only", "workspace", "full"].contains(accessLevel) else { return }
        if sendLocalTaskPreferences(sessionId, changes: ["access_level": accessLevel]) { return }
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
        if sendLocalTaskPreferences(sessionId, changes: ["mcp": ["name": serverName, "allowed": allowed]]) { return }
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
        if sendLocalTaskPreferences(sessionId, changes: ["skill": ["name": skillName, "allowed": allowed]]) { return }
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
        if sendLocalTaskPreferences(sessionId, changes: ["shell_allowed": allowed]) { return }
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
    func mutateSession(_ sessionId: String, _ body: (inout SessionInfo) -> Void) {
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

}

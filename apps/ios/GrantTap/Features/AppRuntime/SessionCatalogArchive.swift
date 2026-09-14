import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func setSessionArchived(_ sessionId: String, _ archived: Bool) {
        if archived {
            archivedSessionIds.insert(sessionId)
            if let session = (sessions + sessionHistory).first(where: { $0.sessionId == sessionId }) {
                archivedSessions[sessionId] = session
            }
        } else {
            // Restore must land somewhere visible — never drop the snapshot.
            archivedSessionIds.remove(sessionId)
            if let snapshot = archivedSessions.removeValue(forKey: sessionId) {
                let inLive = sessions.contains { $0.sessionId == sessionId }
                let inHist = sessionHistory.contains { $0.sessionId == sessionId }
                if !inLive && !inHist {
                    sessions.insert(snapshot, at: 0)
                }
            }
        }
        persistArchivedSessions()
        ArchivedSessionPersistence.save(archivedSessions)
        AuditStore.shared.record("archive", detail: archived ? "Task archived locally" : "Task restored locally")
    }

    func isArchived(_ sessionId: String) -> Bool { archivedSessionIds.contains(sessionId) }

    func sessionsForArchiveView(_ archived: Bool) -> [SessionInfo] {
        if archived {
            return archivedSessions.values.sorted { $0.lastActivityAt > $1.lastActivityAt }
        }
        let active = sessions.filter { !archivedSessionIds.contains($0.sessionId) }
        if !active.isEmpty { return active }
        // Never leave Active blank when Mac catalog/history is known (common after
        // reinstall or when every live row was locally archived).
        if !sessions.isEmpty {
            return sessions.sorted { $0.lastActivityAt > $1.lastActivityAt }
        }
        return Array(allSessionHistory.prefix(24))
    }

    /// A relay refresh should never produce duplicate SwiftUI identities. If
    /// an older helper emits the same session more than once, retain its first
    /// list position but replace the value with the freshest snapshot.
    static func deduplicatedSessions(_ values: [SessionInfo]) -> [SessionInfo] {
        var result: [SessionInfo] = []
        var indexById: [String: Int] = [:]
        for session in values {
            if let index = indexById[session.sessionId] {
                if session.lastActivityAt >= result[index].lastActivityAt {
                    result[index] = session
                }
            } else {
                indexById[session.sessionId] = result.count
                result.append(session)
            }
        }
        return result
    }

    /// Prefer Mac-published MCP/skills when present; otherwise keep the phone's
    /// last list so lean history ticks and Active→History moves do not blank
    /// enable/disable toggles or usage rows.
    static func retainingCapabilities(incoming: SessionInfo, previous: SessionInfo?) -> SessionInfo {
        guard let previous else { return incoming }
        var next = incoming
        let incomingSkills = next.skills ?? []
        if incomingSkills.isEmpty, let kept = previous.skills, !kept.isEmpty {
            next.skills = kept
        }
        let incomingMcp = next.mcpServers ?? []
        if incomingMcp.isEmpty, let kept = previous.mcpServers, !kept.isEmpty {
            next.mcpServers = kept
        }
        if next.shellAllowed == nil, let shell = previous.shellAllowed {
            next.shellAllowed = shell
        }
        return next
    }

    /// Past Mac chats for the History sheet — never Active, never Archive mirror.
    var allSessionHistory: [SessionInfo] {
        let activeIds = Set(sessions.filter { !archivedSessionIds.contains($0.sessionId) }.map(\.sessionId))
        var byId: [String: SessionInfo] = [:]
        for session in sessionHistory where !archivedSessionIds.contains(session.sessionId) {
            if activeIds.contains(session.sessionId) { continue }
            if let previous = byId[session.sessionId], previous.lastActivityAt > session.lastActivityAt { continue }
            byId[session.sessionId] = session
        }
        return byId.values.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    func workspaceFolders(for agent: String) -> [String] {
        let normalized = AgentIdentity.normalize(agent)
        var seen = Set<String>()
        let pool = sessions + sessionHistory + Array(archivedSessions.values)
        return pool.compactMap { session in
            guard AgentIdentity.normalize(session.agent) == normalized,
                  let cwd = session.cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !cwd.isEmpty, seen.insert(cwd).inserted else { return nil }
            return cwd
        }
    }

    func persistArchivedSessions() {
        UserDefaults.standard.set(Array(archivedSessionIds).sorted(), forKey: "granttap.archived-sessions")
    }
}

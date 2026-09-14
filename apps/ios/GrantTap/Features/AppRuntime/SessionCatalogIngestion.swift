import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func purgeDemoCatalogResidue(reason: String) {
        let before = sessions.count + sessionHistory.count
        demoMode = false
        sessions = Self.filterRealCatalogSessions(sessions, allowDemo: false)
        sessionHistory = Self.filterRealCatalogSessions(sessionHistory, allowDemo: false)
        for key in activities.keys where Self.isGrantTapDemoSessionId(key) {
            activities.removeValue(forKey: key)
        }
        SessionCatalogCache.clear()
        let after = sessions.count + sessionHistory.count
        if before != after || reason == "pair" || reason == "stop-demo" {
            append("catalog-isolation: purged demo residue (\(reason)) \(before)→\(after)")
        }
        objectWillChange.send()
    }

    /// Cold-start seed from disk so Active is never blank after reinstall while
    /// the first sessions.status is in flight.
    func loadCachedSessionCatalogIfNeeded() {
        guard sessions.isEmpty, sessionHistory.isEmpty,
              let cached = SessionCatalogCache.load() else { return }
        let before = cached.sessions.count + cached.history.count
        let live = Self.filterRealCatalogSessions(cached.sessions, allowDemo: false)
        let hist = Self.filterRealCatalogSessions(cached.history, allowDemo: false)
        guard !live.isEmpty || !hist.isEmpty else {
            SessionCatalogCache.clear()
            append("catalog-cache: discarded demo/opaque sqlite snapshot (\(before) ghosts)")
            return
        }
        // Rewrite SQLite without code-blob / demo ghosts so they cannot return.
        if live.count + hist.count < before {
            SessionCatalogCache.save(
                sessions: live, history: hist, machine: cached.machine,
                tokensRecent: cached.tokensRecent, tokenWindowHours: cached.tokenWindowHours,
                generatedAt: cached.generatedAt
            )
            append("catalog-cache: purged \(before - live.count - hist.count) ghost rows from sqlite")
        }
        sessions = Self.deduplicatedSessions(live)
        sessionHistory = Self.deduplicatedSessions(hist)
        if machineName.isEmpty { machineName = cached.machine }
        if tokensRecent == 0 { tokensRecent = cached.tokensRecent }
        tokenWindowHours = cached.tokenWindowHours
        lastSessionsGeneratedAt = cached.generatedAt
        append("catalog-cache: sqlite restored \(sessions.count) live / \(sessionHistory.count) history")
    }

    /// Settings → Clear local chat cache (does not affect Mac sessions).
    func clearLocalSessionCache() {
        SessionCatalogCache.clear()
        sessions = []
        sessionHistory = []
        activities = [:]
        lastSessionsGeneratedAt = 0
        append("catalog-cache: cleared")
        AuditStore.shared.record("cache", detail: "Cleared local SQLite session cache")
        pushToWatch()
        // Awaitable refresh so Active repopulates from THIS Mac's lean publish.
        Task { await refreshSessions() }
    }

    private func preparedCatalog(
        from status: SessionsStatus
    ) -> (live: [SessionInfo], history: [SessionInfo]?) {
        var previousById: [String: SessionInfo] = [:]
        for item in self.sessions + self.sessionHistory {
            if let previous = previousById[item.sessionId],
               previous.lastActivityAt > item.lastActivityAt { continue }
            previousById[item.sessionId] = item
        }
        let live = Self.filterRealCatalogSessions(
            Self.deduplicatedSessions(status.sessions),
            allowDemo: demoMode
        ).map {
            Self.retainingCapabilities(incoming: $0, previous: previousById[$0.sessionId])
        }
        let history = status.history.map {
            Self.filterRealCatalogSessions(
                Self.deduplicatedSessions($0),
                allowDemo: demoMode
            ).map {
                Self.retainingCapabilities(incoming: $0, previous: previousById[$0.sessionId])
            }
        }
        return (live, history)
    }

    private func mergedRemoteLive(
        _ decodedLive: [SessionInfo],
        history: [SessionInfo]?
    ) -> [SessionInfo] {
        var remoteLive = decodedLive
        if remoteLive.isEmpty, let history, !history.isEmpty {
            remoteLive = Array(history.prefix(12))
        }
        let preferredPublishing = self.isMacCatalogFresh
            || self.connectionSnapshot.phase == .live
        let existingMac = self.sessions.filter {
            !self.localOnlySessionIds.contains($0.sessionId)
                && !Self.isGrantTapDemoSessionId($0.sessionId)
                && !Self.isCodeBlobCatalogTitle(sessionId: $0.sessionId, title: $0.title)
        }
        if remoteLive.isEmpty && !existingMac.isEmpty && preferredPublishing {
            remoteLive = existingMac
        }
        if remoteLive.isEmpty && !self.sessions.isEmpty && preferredPublishing {
            remoteLive = self.sessions.filter {
                !Self.isGrantTapDemoSessionId($0.sessionId)
                    && !Self.isCodeBlobCatalogTitle(sessionId: $0.sessionId, title: $0.title)
            }
        }
        let pendingLocal = self.sessions.filter { local in
            remoteLive.contains(where: { $0.sessionId == local.sessionId }) == false
                && (
                    self.localOnlySessionIds.contains(local.sessionId)
                        || self.deliveries.contains(where: {
                            $0.sessionId == local.sessionId
                                && ($0.state == .queued || $0.state == .sending || $0.state == .failed)
                        })
                )
        }
        return Self.deduplicatedSessions(remoteLive + pendingLocal)
    }

    private func applyLiveCatalog(_ nextSessions: [SessionInfo]) {
        if nextSessions.isEmpty && !self.sessions.isEmpty {
            append("sessions.status ignored empty live (kept \(self.sessions.count))")
        } else if self.sessions != nextSessions {
            // Several reporters send the same list every few seconds; publishing
            // an unchanged list redraws every screen that shows chats.
            self.sessions = nextSessions
        }
        let liveIds = Set(self.sessions.map(\.sessionId))
        if !self.localOnlySessionIds.isEmpty {
            let before = self.localOnlySessionIds.count
            self.localOnlySessionIds = self.localOnlySessionIds.subtracting(liveIds)
            if self.localOnlySessionIds.count != before { self.persistLocalOnlySessions() }
        }
    }

    private func applyHistoryCatalog(
        _ history: [SessionInfo]?,
        remoteLive: [SessionInfo]
    ) {
        let liveIds = Set(self.sessions.map(\.sessionId))
        if let history, !history.isEmpty {
            self.sessionHistory = history.filter {
                !liveIds.contains($0.sessionId) && !archivedSessionIds.contains($0.sessionId)
            }
        } else if !self.sessionHistory.isEmpty {
            self.sessionHistory = self.sessionHistory.filter {
                !liveIds.contains($0.sessionId) && !archivedSessionIds.contains($0.sessionId)
            }
        }
        var archivedSnapshotChanged = false
        for session in remoteLive + (history ?? [])
        where self.archivedSessionIds.contains(session.sessionId) {
            if self.archivedSessions[session.sessionId] != session {
                self.archivedSessions[session.sessionId] = session
                archivedSnapshotChanged = true
            }
        }
        if archivedSnapshotChanged {
            ArchivedSessionPersistence.save(self.archivedSessions)
        }
    }

    private func applyCatalogConfiguration(
        _ status: SessionsStatus,
        sourceNamespace: String?
    ) {
        self.tokensRecent = status.tokensRecent
        self.tokenWindowHours = status.tokenWindowHours
        self.machineName = status.machine
        if let g = status.gatingEnabled { self.gatingEnabled = g }
        if let ex = status.excludedSessions { self.excludedSessions = ex }
        if let d = status.autoAcceptDefault { self.autoAcceptDefault = d }
        if let m = status.autoAcceptBySession { self.autoAcceptBySession = m }
        if let p = status.autoAcceptPaused { self.autoAcceptPaused = p }
        if let names = status.globalMcpDisabled { self.globalMcpDisabled = Set(names) }
        if let names = status.globalSkillsDisabled { self.globalSkillsDisabled = Set(names) }
        if let disabled = status.globalShellDisabled { self.globalShellDisabled = disabled }
        if let agents = status.agents {
            self.agentIntegrations = agents
            if let room = sourceNamespace { self.agentIntegrationsByRoom[room] = agents }
        }
        if let embedded = status.activities {
            for activity in embedded {
                if let room = sourceNamespace,
                   !acceptsSessionPayload(sessionId: activity.sessionId,
                                          fromRoom: room) { continue }
                applyActivity(activity, sourceNamespace: sourceNamespace)
            }
        }
    }

    private func persistRealCatalog(generatedAt: Double) {
        guard !demoMode else { return }
        let live = Self.filterRealCatalogSessions(self.sessions, allowDemo: false)
        let history = Self.filterRealCatalogSessions(self.sessionHistory, allowDemo: false)
        guard !live.isEmpty || !history.isEmpty else { return }
        SessionCatalogCache.save(
            sessions: live, history: history, machine: self.machineName,
            tokensRecent: self.tokensRecent, tokenWindowHours: self.tokenWindowHours,
            generatedAt: generatedAt
        )
    }

    func applySessionsStatus(_ status: SessionsStatus,
                             sourceNamespace: String? = nil) {
        if !demoMode {
            let hadDemo = sessions.contains(where: { Self.isGrantTapDemoSessionId($0.sessionId) })
                || sessionHistory.contains(where: { Self.isGrantTapDemoSessionId($0.sessionId) })
                || activities.keys.contains(where: { Self.isGrantTapDemoSessionId($0) })
            if hadDemo {
                purgeDemoCatalogResidue(reason: "demoMode-false")
            } else {
                sessions = Self.filterRealCatalogSessions(sessions, allowDemo: false)
                sessionHistory = Self.filterRealCatalogSessions(sessionHistory, allowDemo: false)
            }
        }
        let catalog = preparedCatalog(from: status)
        let remoteLive = mergedRemoteLive(catalog.live, history: catalog.history)
        applyLiveCatalog(remoteLive)
        applyHistoryCatalog(catalog.history, remoteLive: remoteLive)
        applyCatalogConfiguration(status, sourceNamespace: sourceNamespace)
        clearStuckMcpReplies()
        self.lastSessionsGeneratedAt = status.generatedAt
        persistRealCatalog(generatedAt: status.generatedAt)
        self.completeSessionRefreshWaiters()
        self.objectWillChange.send()
        self.pushToWatch()
        self.finishBackgroundWake(.newData)
        // Members who may watch a Project's chats get its part of this list.
        if let room = sourceNamespace { forwardStatusToMembers(fromRoom: room) }
        if !catalog.live.isEmpty || !(catalog.history ?? []).isEmpty {
            append("sessions.status applied live=\(self.sessions.count) history=\(self.sessionHistory.count)")
        } else if self.sessions.isEmpty && self.sessionHistory.isEmpty {
            append("sessions.status applied EMPTY (decode or Mac sparse)")
        }
    }
}

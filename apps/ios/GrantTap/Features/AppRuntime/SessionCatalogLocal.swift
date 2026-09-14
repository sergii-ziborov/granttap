import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func ensureLocalSession(sessionId: String?, agent: String, cwd: String?,
                            title: String?, at: Double) -> String {
        let minted = sessionId == nil
        let id = sessionId ?? UUID().uuidString.lowercased()
        let localState = minted ? "waiting" : "working"
        if minted {
            localOnlySessionIds.insert(id)
            persistLocalOnlySessions()
        }
        if let index = sessions.firstIndex(where: { $0.sessionId == id }) {
            var updated = sessions[index]
            // Keep the first title — later sends must not overwrite the row name.
            if (updated.title == nil || updated.title?.isEmpty == true),
               let title, !title.isEmpty { updated.title = title }
            sessions[index] = updated.replacingLocalSessionValues(
                sessionId: updated.sessionId,
                title: updated.title ?? title,
                cwd: updated.cwd ?? cwd,
                state: localState,
                lastActivityAt: at
            )
            return id
        }
        let stub = SessionInfo(
            sessionId: id,
            agent: agent,
            title: title,
            cwd: cwd,
            branch: nil,
            model: nil,
            summary: nil,
            accessLevel: nil,
            state: localState,
            startedAt: at,
            lastActivityAt: at,
            tokensSession: 0,
            tokensLastTurn: 0,
            contextTokensUsed: nil,
            contextWindow: nil,
            mcpServers: nil,
            skills: nil,
            shellAllowed: true
        )
        sessions.insert(stub, at: 0)
        return id
    }

    func persistLocalOnlySessions() {
        UserDefaults.standard.set(Array(localOnlySessionIds).sorted(),
                                  forKey: "granttap.local-only-sessions")
    }

    /// When Mac answers with a real session id, replace the phone-minted stub.
    /// Multi-agent: never bail when several stubs exist — match open chat, then
    /// in-flight delivery agent, then newest local stub for that agent.
    func adoptMacSessionId(_ realId: String, agent hintAgent: String? = nil) {
        localOnlySessionIds.remove(realId)
        defer { persistLocalOnlySessions() }
        guard !localOnlySessionIds.isEmpty else { return }
        let stubId = resolveLocalStubForAdoption(hintAgent: hintAgent)
        guard let stubId, stubId != realId else { return }
        remapLocalSession(from: stubId, to: realId)
    }

    func resolveLocalStubForAdoption(hintAgent: String?) -> String? {
        if let open = sessionToOpen, localOnlySessionIds.contains(open) {
            return open
        }
        // Prefer the stub of the most recent in-flight / just-delivered outbox row.
        if let deliveryStub = deliveries.first(where: { d in
            guard let sid = d.sessionId, localOnlySessionIds.contains(sid) else { return false }
            return d.state == .sending || d.state == .queued || d.state == .delivered
        })?.sessionId {
            return deliveryStub
        }
        let agentHint = hintAgent.flatMap { AgentIdentity.normalize($0) }
            ?? deliveries.first(where: { d in
                d.sessionId.map { localOnlySessionIds.contains($0) } == true
            }).flatMap { d in
                d.agent.map(AgentIdentity.normalize)
                    ?? d.sessionId.flatMap { sid in
                        sessions.first(where: { $0.sessionId == sid }).map {
                            AgentIdentity.normalize($0.agent)
                        }
                    }
            }
        if let agentHint,
           let match = sessions.first(where: {
               localOnlySessionIds.contains($0.sessionId)
                   && AgentIdentity.normalize($0.agent) == agentHint
           }) {
            return match.sessionId
        }
        if localOnlySessionIds.count == 1 {
            return localOnlySessionIds.first
        }
        // Last resort: newest local-only row (sessions are newest-first).
        return sessions.first(where: { localOnlySessionIds.contains($0.sessionId) })?.sessionId
    }

    func remapLocalSession(from oldId: String, to newId: String) {
        let remappedAt = Date().timeIntervalSince1970 * 1000
        let deferredFollowUpIds = deliveries
            .filter {
                $0.sessionId == oldId
                    && $0.awaitingSessionRemap == true
                    && $0.state == .queued
            }
            .sorted {
                if $0.createdAt == $1.createdAt { return $0.id < $1.id }
                return $0.createdAt < $1.createdAt
            }
            .map(\.id)
        // Commit the native route before clearing the persisted local-only bit or
        // aliases. A crash can therefore leave either the old fully blocked state
        // or the new native route, never an unblocked phone UUID on the wire.
        for i in deliveries.indices where deliveries[i].sessionId == oldId {
            let d = deliveries[i]
            deliveries[i] = OutgoingDelivery(
                id: d.id, text: d.text, agent: d.agent, cwd: d.cwd,
                sessionId: newId, requestId: d.requestId, roomId: d.roomId,
                attachments: d.attachments,
                preferredMcp: d.preferredMcp, skill: d.skill, createdAt: d.createdAt,
                updatedAt: d.awaitingSessionRemap == true ? remappedAt : d.updatedAt,
                attempts: d.attempts, state: d.state,
                error: d.error, nextRetryAt: d.nextRetryAt,
                processingAcknowledgedAt: d.processingAcknowledgedAt,
                processingRetryStartedAt: d.processingRetryStartedAt,
                admissionRejected: d.admissionRejected,
                attemptGeneration: d.attemptGeneration,
                awaitingSessionRemap: d.awaitingSessionRemap == true
                    ? false : d.awaitingSessionRemap
            )
        }
        persistDeliveries()

        remapSessionSourceRooms(from: oldId, to: newId)
        // Keep open TaskChatView / detail sheets sending to the Mac id.
        sessionIdAliases[oldId] = newId
        // Collapse any prior aliases that pointed at the stub.
        for (key, value) in sessionIdAliases where value == oldId {
            sessionIdAliases[key] = newId
        }
        persistSessionIdAliases()
        // Persist the alias before clearing local-only protection. After any
        // crash boundary, an old UI stub therefore either still wires as a new
        // task (session omitted) or resolves to native — never as a dead stub.
        localOnlySessionIds.remove(oldId)
        localOnlySessionIds.remove(newId)
        persistLocalOnlySessions()

        if let index = sessions.firstIndex(where: { $0.sessionId == oldId }) {
            let old = sessions.remove(at: index)
            if !sessions.contains(where: { $0.sessionId == newId }) {
                sessions.insert(
                    old.remappingLocalSessionRoot(to: newId),
                    at: 0
                )
            }
        }

        if let activity = activities.removeValue(forKey: oldId) {
            var next = activities
            if let existing = next[newId] {
                next[newId] = Self.mergeActivity(existing: existing, incoming: SessionActivity(
                    type: activity.type, sessionId: newId, agent: activity.agent,
                    state: activity.state, entries: activity.entries,
                    generatedAt: activity.generatedAt
                ))
            } else {
                next[newId] = SessionActivity(
                    type: activity.type, sessionId: newId, agent: activity.agent,
                    state: activity.state, entries: activity.entries,
                    generatedAt: activity.generatedAt
                )
            }
            activities = next
            objectWillChange.send()
        }
        if sessionToOpen == oldId { sessionToOpen = newId }
        // Keep subscription heartbeats on the Mac id after remap.
        if let sources = activitySubscribers.removeValue(forKey: oldId) {
            activitySubscribers[newId] = (activitySubscribers[newId] ?? []).union(sources)
            let sourceRelay = relayForSession(newId)
            sourceRelay?.sendSubscription(sessionId: newId, active: true)
            sourceRelay?.requestSessionEvents(sessionId: newId)
        }
        resumeDeferredFollowUps(deferredFollowUpIds)
    }
}

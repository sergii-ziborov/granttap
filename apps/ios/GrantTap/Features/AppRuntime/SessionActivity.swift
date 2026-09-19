import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func recordCapabilityUsage(from activity: SessionActivity,
                               sourceNamespace: String? = nil) {
        var incoming: [RemoteCapabilityUsageEvent] = []
        for entry in activity.entries {
            if let capabilities = entry.capabilities, !capabilities.isEmpty {
                for (index, capability) in capabilities.enumerated() {
                    incoming.append(RemoteCapabilityUsageEvent(
                        // The bridge uses the tool call sourceId as the activity
                        // entry id and for capability.usage.status. Preserve it
                        // when there is one observation so the two encrypted
                        // delivery paths converge instead of counting one call
                        // twice. Multi-capability legacy rows still get suffixes.
                        sourceId: capabilities.count == 1
                            ? entry.id
                            : "\(entry.id):capability:\(index)",
                        sessionId: activity.sessionId,
                        agent: activity.agent,
                        kind: capability.kind,
                        name: capability.name,
                        toolName: capability.toolName,
                        commandPreview: capability.commandPreview,
                        createdAt: entry.createdAt,
                        estimatedContextTokens: capability.estimatedContextTokens
                            ?? entry.estimatedContextTokens,
                        estimatedBaselineTokens: capability.estimatedBaselineTokens,
                        durationMs: capability.durationMs ?? entry.durationMs,
                        outcome: capability.outcome ?? entry.outcome,
                        errorClass: capability.errorClass ?? entry.errorClass,
                        resource: capability.resource
                    ))
                }
                continue
            }
            let kindAndName: (CapabilityUsageKind, String)? = {
                if let server = entry.mcpServer { return (.mcp, server) }
                if let skill = entry.skill { return (.skill, skill) }
                if entry.kind == "tool", let tool = entry.toolName,
                   Self.isLegacyShellToolName(tool) {
                    return (.cli, tool)
                }
                return nil
            }()
            if let (kind, name) = kindAndName {
                incoming.append(RemoteCapabilityUsageEvent(
                    sourceId: entry.id,
                    sessionId: activity.sessionId,
                    agent: activity.agent,
                    kind: kind,
                    name: name,
                    toolName: entry.toolName ?? name,
                    // Older activity payloads did not carry a separately
                    // sanitized command field. Never persist their arbitrary
                    // display text as a command preview.
                    commandPreview: nil,
                    createdAt: entry.createdAt,
                    estimatedContextTokens: entry.estimatedContextTokens,
                    estimatedBaselineTokens: nil,
                    durationMs: entry.durationMs,
                    outcome: entry.outcome,
                    errorClass: entry.errorClass
                ))
            }
        }
        CapabilityUsageStore.shared.merge(incoming, sourceNamespace: sourceNamespace)
    }

    static func isLegacyShellToolName(_ raw: String) -> Bool {
        let names: Set<String> = [
            "bash", "shell", "powershell", "terminal", "exec_command",
            "execute_command", "local_shell_call", "run_command",
            "run_in_terminal", "run_terminal_cmd", "shell_command",
        ]
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if names.contains(normalized) { return true }
        let leaf = normalized.split(whereSeparator: { character in
            character == "." || character == ":" || character == "/"
        }).last.map(String.init)
        return leaf.map(names.contains) ?? false
    }

    func applyActivity(_ activity: SessionActivity, sourceNamespace: String? = nil) {
        if let room = sourceNamespace {
            rememberSessionSourceRoom(room, sessionId: activity.sessionId)
        }
        // Usage is independent of whether the detail screen happens to be open.
        recordCapabilityUsage(from: activity, sourceNamespace: sourceNamespace)
        // Never replace a loaded transcript with an empty "missing session" ack
        // (publishSessionEvents used to send entries=[] when resolve failed).
        let before = self.activities[activity.sessionId]?.entries.count ?? 0
        if activity.entries.isEmpty, before > 0 {
            append("activity.apply keep \(activity.sessionId.prefix(8)) empty-incoming (had \(before))")
            return
        }
        if activity.entries.isEmpty, before == 0 {
            // Only an opened chat stores an empty ack. A catalog tick used to
            // mark every Now card "No messages loaded" before anyone opened it.
            let opened = activitySubscribers[activity.sessionId]?.contains(where: {
                $0.hasPrefix("phone-chat:") || $0.hasPrefix("phone-history:")
            }) == true
            if opened {
                var next = self.activities
                next[activity.sessionId] = activity
                self.activities = next
                SessionActivityPersistence.save(next)
            }
            pruneStaleDeliveries()
            self.finishBackgroundWake(.newData)
            return
        }
        // Members who may watch this chat see the transcript as it changes.
        if let room = sourceNamespace { forwardActivityToMembers(activity, fromRoom: room) }
        // Full dictionary reassignment — subscript mutation of @Published
        // dictionaries often fails to refresh SwiftUI (static chats).
        var next = self.activities
        let merged: SessionActivity
        if let existing = next[activity.sessionId] {
            let reconciled = reconcileOptimisticUserBubbles(
                existing: existing,
                incoming: activity,
                sourceNamespace: sourceNamespace
            )
            let withoutLocalEchoes = reconcileCompletedLocalEchoes(
                existing: reconciled,
                incoming: activity
            )
            merged = Self.mergeActivity(existing: withoutLocalEchoes, incoming: activity)
            // Same transcript snapshot — skip reassignment (chat flicker).
            if merged.entries == existing.entries,
               merged.state == existing.state {
                pruneStaleDeliveries()
                self.finishBackgroundWake(.newData)
                return
            }
            next[activity.sessionId] = merged
        } else {
            merged = activity
            next[activity.sessionId] = activity
        }
        self.activities = next
        // The phone is the only durable holder: the relay stores nothing and the
        // Mac's own copy can be compacted away.
        SessionActivityPersistence.save(next)
        let after = next[activity.sessionId]?.entries.count ?? 0
        if after != before {
            append("activity.apply \(activity.sessionId.prefix(8)) entries=\(before)→\(after)")
        }
        pruneStaleDeliveries()
        self.pushToWatch()
        self.finishBackgroundWake(.newData)
    }

    /// Replace only the optimistic row owned by the delivery that best matches
    /// each provider transcript echo. Text-only global dedupe would collapse
    /// legitimate repeated messages, so identity, route, session and time are
    /// all part of the match and every delivery can be consumed at most once.
    /// A busy chat can queue a message for the whole delivery lifetime before it
    /// reaches the transcript, so a fixed window anchored on send time misses it.
    static let echoSkewMs = 20 * 60 * 1_000.0

    /// Distance between a delivery and a transcript echo, measured from whichever
    /// of the delivery's timestamps is closest: a queued message enters the log
    /// around when it was actually delivered, not when it was sent.
    static func echoSkew(_ delivery: OutgoingDelivery, remoteAt: Double) -> Double {
        let anchors = [delivery.createdAt, delivery.updatedAt,
                       delivery.processingAcknowledgedAt].compactMap { $0 }
        return anchors.map { abs($0 - remoteAt) }.min() ?? .greatestFiniteMagnitude
    }

    static func echoMatches(_ delivery: OutgoingDelivery, remoteAt: Double) -> Bool {
        echoSkew(delivery, remoteAt: remoteAt) <= echoSkewMs
    }

    func reconcileOptimisticUserBubbles(
        existing: SessionActivity,
        incoming: SessionActivity,
        sourceNamespace: String?
    ) -> SessionActivity {
        let remoteUserEntries = incoming.entries.filter {
            ($0.kind == "user" || $0.kind == "message")
                && !$0.id.hasPrefix("local-user-")
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { $0.createdAt < $1.createdAt }
        guard !remoteUserEntries.isEmpty else { return existing }

        let resolvedIncoming = resolvedSessionId(incoming.sessionId)
        let candidateDeliveries = deliveries.filter { delivery in
            guard let sessionId = delivery.sessionId,
                  resolvedSessionId(sessionId) == resolvedIncoming else { return false }
            if let sourceNamespace, let deliveryRoom = delivery.roomId,
               sourceNamespace != deliveryRoom { return false }
            return existing.entries.contains {
                $0.id == "local-user-\(delivery.id)"
                    || $0.id.hasPrefix("local-user-\(delivery.id)-")
            }
        }
        guard !candidateDeliveries.isEmpty else { return existing }

        var consumed = Set<String>()
        for remote in remoteUserEntries {
            let text = remote.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let match = candidateDeliveries
                .filter {
                    !consumed.contains($0.id)
                        && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == text
                        && Self.echoMatches($0, remoteAt: remote.createdAt)
                }
                .min {
                    Self.echoSkew($0, remoteAt: remote.createdAt)
                        < Self.echoSkew($1, remoteAt: remote.createdAt)
                }
            if let match { consumed.insert(match.id) }
        }
        guard !consumed.isEmpty else { return existing }
        let retained = existing.entries.filter { entry in
            !consumed.contains { deliveryId in
                entry.id == "local-user-\(deliveryId)"
                    || entry.id.hasPrefix("local-user-\(deliveryId)-")
            }
        }
        return SessionActivity(
            type: existing.type,
            sessionId: existing.sessionId,
            agent: existing.agent,
            state: existing.state,
            entries: retained,
            generatedAt: existing.generatedAt
        )
    }

    /// Provider logs eventually contain the same user/assistant lines that the
    /// phone rendered optimistically. Once the outbox row is complete, converge
    /// those two stable sources without collapsing legitimate repeated text.
    func reconcileCompletedLocalEchoes(
        existing: SessionActivity,
        incoming: SessionActivity
    ) -> SessionActivity {
        // Same reason as reconcileOptimisticUserBubbles: a queued message's echo
        // lands long after the optimistic bubble, so the window must cover the
        // delivery lifetime, not a few minutes.
        let maximumEchoSkewMs = Self.echoSkewMs
        var consumed = Set<String>()
        let activeLocalIds = Set(deliveries.map { "local-user-\($0.id)" })
        let local = existing.entries.filter { entry in
            // Every relayed agent bubble converges, not only the ones bound to
            // an origin delivery: a reply produced without one is still the same
            // line the provider log is about to show.
            if entry.id.hasPrefix("agent-event-") { return true }
            guard entry.id.hasPrefix("local-user-") else { return false }
            return !activeLocalIds.contains { activeId in
                entry.id == activeId || entry.id.hasPrefix("\(activeId)-")
            }
        }
        for remote in incoming.entries where !remote.id.hasPrefix("local-user-") {
            let remoteIsUser = remote.kind == "user"
            let remoteIsAgent = remote.kind == "message" || remote.kind == "final"
            guard remoteIsUser || remoteIsAgent else { continue }
            let text = remote.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let match = local.filter { candidate in
                guard !consumed.contains(candidate.id),
                      candidate.text.trimmingCharacters(in: .whitespacesAndNewlines) == text else {
                    return false
                }
                if remoteIsUser {
                    // A repeated user line is legitimate, so keep the time bound
                    // that stops two identical sends collapsing into one.
                    return candidate.id.hasPrefix("local-user-")
                        && abs(candidate.createdAt - remote.createdAt) <= maximumEchoSkewMs
                }
                // The transcript is the source of truth for an answer. The bridge
                // durably replays a short reply like "ok", and its matching
                // transcript row can scroll out of the bounded window, so a time
                // bound leaves the relayed copy stranded as a permanent duplicate.
                // Same text in the same chat is enough to converge them.
                return candidate.id.hasPrefix("agent-event-")
            }.min {
                abs($0.createdAt - remote.createdAt) < abs($1.createdAt - remote.createdAt)
            }
            if let match { consumed.insert(match.id) }
        }
        guard !consumed.isEmpty else { return existing }
        return SessionActivity(
            type: existing.type,
            sessionId: existing.sessionId,
            agent: existing.agent,
            state: existing.state,
            entries: existing.entries.filter { !consumed.contains($0.id) },
            generatedAt: existing.generatedAt
        )
    }

    /// Local optimistic / agent.event chat lines — must mutate via full dict
    /// reassignment so SwiftUI refreshes (same static-chat bug as applyActivity).
}

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
        defer { replicaActivityArrived(activity) }
        if let room = sourceNamespace {
            rememberSessionSourceRoom(room, sessionId: activity.sessionId)
        }
        // Usage is independent of whether the detail screen happens to be open.
        recordCapabilityUsage(from: activity, sourceNamespace: sourceNamespace)
        // Never replace a loaded transcript with an empty "missing session" ack
        // (publishSessionEvents used to send entries=[] when resolve failed).
        let before = self.activities[activity.sessionId]?.entries.count ?? 0
        if activity.entries.isEmpty, before > 0, activity.history == nil {
            append("activity.apply keep \(activity.sessionId.prefix(8)) empty-incoming (had \(before))")
            return
        }
        if activity.entries.isEmpty, before == 0 {
            // Store the empty snapshot so History / full-chat can leave the spinner
            // and the user can retry — dropping it left "Opening…" forever.
            var next = self.activities
            next[activity.sessionId] = activity
            self.activities = next
            SessionActivityPersistence.save([activity.sessionId: activity])
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
            // Retain a fresh receipt even if the visible transcript is unchanged.
            if merged.entries == existing.entries,
               merged.state == existing.state, merged.history == existing.history,
               merged.generatedAt == existing.generatedAt {
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
        SessionActivityPersistence.save([activity.sessionId: merged])
        let after = next[activity.sessionId]?.entries.count ?? 0
        if after != before {
            append("activity.apply \(activity.sessionId.prefix(8)) entries=\(before)→\(after)")
        }
        pruneStaleDeliveries()
        self.pushToWatch()
        self.finishBackgroundWake(.newData)
    }

}

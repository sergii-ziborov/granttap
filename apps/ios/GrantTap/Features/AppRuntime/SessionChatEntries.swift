import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func appendLocalChatEntry(sessionId: String, agent: String, entryId: String,
                              kind: String, text: String, createdAt: Double,
                              attachments: [String] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A photo with no caption is still a message; only drop a row that has
        // neither text nor an attachment to show.
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        let carried = attachments.isEmpty ? nil : attachments
        // Always append — never replace a prior user bubble with the same text.
        // If entryId collides (shouldn't), mint a unique suffix.
        var id = entryId
        var next = activities
        if let existing = next[sessionId] {
            if existing.entries.contains(where: { $0.id == id }) {
                id = "\(entryId)-\(Int(createdAt))-\(existing.entries.count)"
            }
            var entries = existing.entries
            entries.append(ActivityEntry(id: id, kind: kind, text: trimmed,
                                         createdAt: createdAt, attachments: carried))
            entries.sort { $0.createdAt < $1.createdAt }
            next[sessionId] = SessionActivity(
                type: existing.type.isEmpty ? "session.activity" : existing.type,
                sessionId: sessionId,
                agent: existing.agent.isEmpty ? agent : existing.agent,
                state: kind == "status" ? "waiting" : "working",
                entries: entries,
                generatedAt: max(existing.generatedAt, createdAt)
            )
        } else {
            next[sessionId] = SessionActivity(
                type: "session.activity",
                sessionId: sessionId,
                agent: agent,
                state: kind == "status" ? "waiting" : "working",
                entries: [ActivityEntry(id: id, kind: kind, text: trimmed,
                                        createdAt: createdAt, attachments: carried)],
                generatedAt: createdAt
            )
        }
        activities = next
        pushToWatch()
    }

    /// Union by entry id; prefer newer generatedAt snapshot metadata.
    /// Local optimistic `local-user-*` bubbles are never dropped by a sparser Mac snapshot.
    static func mergeActivity(existing: SessionActivity, incoming: SessionActivity) -> SessionActivity {
        if incoming.generatedAt < existing.generatedAt,
           incoming.entries.count <= existing.entries.count {
            return existing
        }
        var byId: [String: ActivityEntry] = [:]
        var existingOrder: [String: Int] = [:]
        var incomingOrder: [String: Int] = [:]
        for (index, entry) in existing.entries.enumerated() {
            byId[entry.id] = entry
            existingOrder[entry.id] = index
        }
        for (index, entry) in incoming.entries.enumerated() {
            byId[entry.id] = entry
            incomingOrder[entry.id] = index
        }
        // Re-assert phone-local user rows in case an older merge path wiped them.
        for entry in existing.entries
        where entry.id.hasPrefix("local-user-")
            || (entry.kind == "user" && incomingOrder[entry.id] == nil) {
            byId[entry.id] = entry
        }
        let merged = byId.values.sorted { left, right in
            if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
            // Several visible blocks from one provider row intentionally share
            // a timestamp. Keep the bridge's transcript order across periodic
            // snapshots; Dictionary.values would otherwise scramble the chat.
            if let leftIndex = incomingOrder[left.id],
               let rightIndex = incomingOrder[right.id] {
                return leftIndex < rightIndex
            }
            if let leftIndex = existingOrder[left.id],
               let rightIndex = existingOrder[right.id] {
                return leftIndex < rightIndex
            }
            return left.id < right.id
        }
        let state = incoming.generatedAt >= existing.generatedAt ? incoming.state : existing.state
        let generatedAt = max(existing.generatedAt, incoming.generatedAt)
        return SessionActivity(
            type: incoming.type.isEmpty ? existing.type : incoming.type,
            sessionId: incoming.sessionId,
            agent: incoming.agent.isEmpty ? existing.agent : incoming.agent,
            state: state,
            // The computer sends a short window each time, but merging them
            // accumulates, and a long-running chat has no natural end. Keep the
            // newest window in memory as well as on disk, cut from the front so
            // the part being read always survives.
            entries: merged.count > SessionActivityPersistence.maxEntriesPerSession
                ? Array(merged.suffix(SessionActivityPersistence.maxEntriesPerSession))
                : merged,
            generatedAt: generatedAt
        )
    }
}

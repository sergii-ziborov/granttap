import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func appendLocalChatEntry(sessionId: String, agent: String, entry: ActivityEntry) {
        let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A photo with no caption is still a message; only drop a row that has
        // neither text nor an attachment to show.
        guard !trimmed.isEmpty || entry.attachments?.isEmpty == false else { return }
        let carried = entry.attachments?.isEmpty == true ? nil : entry.attachments
        // Always append — never replace a prior user bubble with the same text.
        // If entryId collides (shouldn't), mint a unique suffix.
        var id = entry.id
        var next = activities
        if let existing = next[sessionId] {
            if existing.entries.contains(where: { $0.id == id }) {
                id = "\(entry.id)-\(Int(entry.createdAt))-\(existing.entries.count)"
            }
            var entries = existing.entries
            entries.append(ActivityEntry(id: id, kind: entry.kind, text: trimmed,
                                         createdAt: entry.createdAt, attachments: carried))
            entries.sort { $0.createdAt < $1.createdAt }
            next[sessionId] = SessionActivity(
                type: existing.type.isEmpty ? "session.activity" : existing.type,
                sessionId: sessionId,
                agent: existing.agent.isEmpty ? agent : existing.agent,
                state: entry.kind == "status" ? "waiting" : "working",
                entries: entries,
                generatedAt: max(existing.generatedAt, entry.createdAt), history: existing.history
            )
        } else {
            next[sessionId] = SessionActivity(
                type: "session.activity",
                sessionId: sessionId,
                agent: agent,
                state: entry.kind == "status" ? "waiting" : "working",
                entries: [ActivityEntry(id: id, kind: entry.kind, text: trimmed,
                                        createdAt: entry.createdAt, attachments: carried)],
                generatedAt: entry.createdAt
            )
        }
        activities = next
        pushToWatch()
    }

    /// Union by entry id; prefer newer generatedAt snapshot metadata.
    /// Local optimistic `local-user-*` bubbles are never dropped by a sparser Mac snapshot.
    static func mergeActivity(existing: SessionActivity, incoming: SessionActivity) -> SessionActivity {
        if incoming.generatedAt < existing.generatedAt,
           incoming.entries.count <= existing.entries.count, incoming.history == nil {
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
            if incoming.agent == "codex", incoming.history != nil {
                for old in existing.entries where Self.isLegacyCodexAlias(old, of: entry, sessionId: incoming.sessionId) {
                    byId.removeValue(forKey: old.id)
                }
            }
            if incoming.generatedAt >= existing.generatedAt || byId[entry.id] == nil {
                byId[entry.id] = SessionActivityTelemetry.retaining(entry, from: byId[entry.id])
            }
            incomingOrder[entry.id] = index
        }
        // Re-assert phone-local user rows in case an older merge path wiped them.
        for entry in existing.entries
        where entry.id.hasPrefix("local-user-")
            || (entry.kind == "user" && incomingOrder[entry.id] == nil && byId[entry.id] != nil) {
            byId[entry.id] = entry
        }
        let isOlderPage = incoming.history?.requestedCursor != nil
        let orderedIds = isOlderPage
            ? incoming.entries.map(\.id) + existing.entries.filter { incomingOrder[$0.id] == nil }.map(\.id)
            : existing.entries.filter { incomingOrder[$0.id] == nil }.map(\.id) + incoming.entries.map(\.id)
        let ranks = Dictionary(orderedIds.enumerated().map { ($0.element, $0.offset) },
                               uniquingKeysWith: { first, _ in first })
        let merged = byId.values.sorted { left, right in
            if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
            // Several visible blocks from one provider row intentionally share
            // a timestamp. Keep the bridge's transcript order across periodic
            // snapshots; Dictionary.values would otherwise scramble the chat.
            return (ranks[left.id] ?? 0) < (ranks[right.id] ?? 0)
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
            entries: incoming.history == nil && existing.history == nil
                && merged.count > SessionActivityPersistence.maxEntriesPerSession
                ? Array(merged.suffix(SessionActivityPersistence.maxEntriesPerSession))
                : merged,
            generatedAt: generatedAt,
            history: isOlderPage || existing.history == nil ? incoming.history : existing.history
        )
    }

    /// Old window-relative ids and native ids can describe the same visible block.
    /// Timestamp, block number and contents must all agree; repeated turns remain distinct.
    private static func isLegacyCodexAlias(_ old: ActivityEntry, of native: ActivityEntry, sessionId: String) -> Bool {
        let prefix = sessionId + ":"
        guard old.id != native.id, old.id.hasPrefix(prefix), native.id.hasPrefix(prefix),
              old.createdAt == native.createdAt, old.text == native.text,
              old.childThreadId == native.childThreadId,
              old.kind == native.kind || old.kind == "message" && native.kind == "final" else { return false }
        let legacy = old.id.dropFirst(prefix.count).split(separator: ":")
        let current = native.id.dropFirst(prefix.count).split(separator: ":")
        guard legacy.count == 2, current.count == 3, legacy[0] == current[0],
              current[1].count == 16, current[1].allSatisfy({ $0.isHexDigit }),
              let ordinal = Int(legacy[1]), let block = Int(current[2]) else { return false }
        return ordinal % 100 == block
    }

    /// Loaded older pages are held while reading; closing the chat releases them.
    func releaseTranscriptHistory(sessionId: String) {
        guard let activity = activities[sessionId], activity.history != nil else { return }
        activities[sessionId] = SessionActivity(type: activity.type, sessionId: sessionId,
            agent: activity.agent, state: activity.state,
            entries: Array(activity.entries.suffix(SessionActivityPersistence.maxEntriesPerSession)),
            generatedAt: activity.generatedAt)
    }
}

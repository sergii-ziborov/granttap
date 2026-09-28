import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func rememberRequestSourceRoom(_ room: String, requestId: String) {
        guard !room.isEmpty, !requestId.isEmpty else { return }
        requestSourceRoom[requestId] = room
        UserDefaults.standard.set(requestSourceRoom, forKey: "granttap.request-source-rooms")
    }

    func forgetRequestSourceRoom(_ requestId: String) {
        requestSourceRoom[requestId] = nil
        UserDefaults.standard.set(requestSourceRoom, forKey: "granttap.request-source-rooms")
    }

    func rememberSessionSourceRoom(_ room: String, sessionId: String) {
        rememberSessionSourceRooms(room, sessionIds: [sessionId])
    }

    func rememberSessionSourceRooms(_ room: String, sessionIds: [String]) {
        guard !room.isEmpty else { return }
        var changed = false
        for raw in sessionIds {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let resolved = resolvedSessionId(trimmed)
            for id in Set([trimmed, resolved]) {
                var rooms = Set(sessionSourceRooms[id] ?? [])
                if rooms.insert(room).inserted {
                    sessionSourceRooms[id] = rooms.sorted()
                    changed = true
                }
            }
        }
        if changed {
            UserDefaults.standard.set(sessionSourceRooms,
                                      forKey: "granttap.session-source-rooms")
        }
    }

    /// Exact ownership state for a raw provider id. Removed rooms are ignored at
    /// read time as a migration guard; cleanup also rewrites the persisted map.
    func sessionRoomOwnership(forSessionId sessionId: String) -> SessionRoomOwnership {
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }
        let resolved = resolvedSessionId(trimmed)
        var rooms = Set(sessionSourceRooms[trimmed] ?? [])
        rooms.formUnion(sessionSourceRooms[resolved] ?? [])
        rooms.formIntersection(connectionRegistry.connections.map(\.id))
        switch rooms.count {
        case 0: return .unknown
        case 1: return .exact(rooms.first!)
        default: return .ambiguous(rooms.sorted())
        }
    }

    /// Convenience for callers that only have a safe path for exact ownership.
    func sourceRoom(forSessionId sessionId: String) -> String? {
        sessionRoomOwnership(forSessionId: sessionId).exactRoom
    }

    /// Authenticate every transcript path consistently, including activities
    /// embedded in sessions.status (which do not pass through onActivity).
    func acceptsSessionPayload(sessionId: String, fromRoom room: String) -> Bool {
        switch sessionRoomOwnership(forSessionId: sessionId) {
        case .exact(let owner):
            return owner == room
        case .ambiguous:
            return false
        case .unknown:
            let legacyRoom = connectionRegistry.preferredId
                ?? (connectionRegistry.connections.count == 1
                    ? connectionRegistry.connections.first?.id : nil)
            return legacyRoom == room
        }
    }

    func relayForSession(_ sessionId: String) -> RelayClient? {
        switch sessionRoomOwnership(forSessionId: sessionId) {
        case .exact(let room):
            return relaysByRoom[room]
        case .ambiguous:
            return nil
        case .unknown:
            break
        }
        // Legacy local state can be migrated only when there is exactly one
        // possible destination. With 2+ rooms, fail closed.
        guard connectionRegistry.connections.count == 1,
              let room = connectionRegistry.connections.first?.id else { return nil }
        rememberSessionSourceRoom(room, sessionId: sessionId)
        return relaysByRoom[room]
    }

    /// Capability rows in a chat are a two-part identity: authenticated room +
    /// native session id. Nil-room legacy/global observations deliberately stay
    /// visible only in the aggregate Usage screen, never in every chat.
    func capabilityUsageEvents(forSessionId sessionId: String) -> [CapabilityUsageEvent] {
        guard case .exact(let room) = sessionRoomOwnership(forSessionId: sessionId) else {
            return []
        }
        let resolved = resolvedSessionId(sessionId)
        var ids: Set<String> = [sessionId, resolved]
        for (alias, target) in sessionIdAliases
        where target == resolved || alias == sessionId || alias == resolved {
            ids.insert(alias)
            ids.insert(target)
        }
        return CapabilityUsageStore.shared.events.filter { event in
            guard event.sourceRoom == room, let eventSession = event.sessionId else {
                return false
            }
            return ids.contains(eventSession) || resolvedSessionId(eventSession) == resolved
        }
    }

    /// Remove ownership from unlinked rooms while retaining known ownership for
    /// rooms that are still linked. Active outbox rows re-assert their immutable
    /// room pin, so cleanup can never retarget a retry.
    func pruneSessionSourceRoomsToLinkedRooms() {
        rebuildSessionSourceRooms(keepKnownLinkedOwners: true)
    }

    /// A preferred-catalog change invalidates every catalog-derived owner. Only
    /// room pins belonging to active deliveries survive until the new preferred
    /// room publishes its authenticated catalog.
    func resetSessionSourceRoomsForCatalogSwitch() {
        rebuildSessionSourceRooms(keepKnownLinkedOwners: false)
    }

    func rebuildSessionSourceRooms(keepKnownLinkedOwners: Bool) {
        let linkedRooms = Set(connectionRegistry.connections.map(\.id))
        var next: [String: Set<String>] = [:]
        if keepKnownLinkedOwners {
            for (sessionId, storedRooms) in sessionSourceRooms {
                let rooms = Set(storedRooms).intersection(linkedRooms)
                if !rooms.isEmpty { next[sessionId] = rooms }
            }
        }

        for delivery in deliveries {
            guard delivery.state != .delivered
                    || delivery.sessionId.map({ localOnlySessionIds.contains($0) }) == true,
                  let sessionId = delivery.sessionId,
                  let room = delivery.roomId,
                  linkedRooms.contains(room) else { continue }
            let resolved = resolvedSessionId(sessionId)
            for id in Set([sessionId, resolved]) {
                next[id, default: []].insert(room)
            }
        }

        sessionSourceRooms = next.mapValues { $0.sorted() }
        if sessionSourceRooms.isEmpty {
            UserDefaults.standard.removeObject(forKey: "granttap.session-source-rooms")
        } else {
            UserDefaults.standard.set(sessionSourceRooms,
                                      forKey: "granttap.session-source-rooms")
        }
    }

    func roomId(for client: RelayClient) -> String? {
        relaysByRoom.first(where: { $0.value === client })?.key
    }

    func remapSessionSourceRooms(from oldId: String, to newId: String) {
        let rooms = Set(sessionSourceRooms[oldId] ?? [])
        guard !rooms.isEmpty else { return }
        var next = Set(sessionSourceRooms[newId] ?? [])
        next.formUnion(rooms)
        sessionSourceRooms[newId] = next.sorted()
        UserDefaults.standard.set(sessionSourceRooms,
                                  forKey: "granttap.session-source-rooms")
    }

    func cancellationKey(_ requestId: String, room: String?) -> String {
        "\(room ?? "legacy")|\(requestId)"
    }

    func requestBelongsToSource(_ requestId: String, room: String?) -> Bool {
        guard let mapped = requestSourceRoom[requestId] else { return true }
        guard let room else { return false }
        return mapped == room
    }

    static func normalizedApprovalSession(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func approvalScopeKey(_ requestId: String, sessionId: String?) -> String {
        "\(requestId)\u{1f}\(normalizedApprovalSession(sessionId) ?? "")"
    }

    func approvalTerminalKey(_ requestId: String, room: String?,
                                     sessionId: String?) -> String {
        "\(room ?? "legacy")\u{1f}\(Self.approvalScopeKey(requestId, sessionId: sessionId))"
    }

    func persistApprovalConvergenceState() {
        UserDefaults.standard.set(approvalStatusWatermarkByRoom,
                                  forKey: "granttap.approval-status-watermarks")
        UserDefaults.standard.set(approvalTerminalTombstones,
                                  forKey: "granttap.approval-terminal-tombstones")
    }

    func pruneApprovalTerminalTombstones(nowMs: Double) {
        let recent = approvalTerminalTombstones.filter {
            nowMs - $0.value <= Self.approvalTombstoneRetentionMs
        }
        approvalTerminalTombstones = Dictionary(
            uniqueKeysWithValues: recent
                .sorted { $0.value > $1.value }
                .prefix(Self.approvalTombstoneLimit)
                .map { ($0.key, $0.value) }
        )
    }

    func markApprovalTerminal(_ requestId: String, room: String?,
                                      sessionId: String?) {
        let nowMs = Date().timeIntervalSince1970 * 1_000
        approvalTerminalTombstones[
            approvalTerminalKey(requestId, room: room, sessionId: sessionId)
        ] = nowMs
        pruneApprovalTerminalTombstones(nowMs: nowMs)
        persistApprovalConvergenceState()
    }

    func wasApprovalTerminal(_ requestId: String, room: String?,
                                     sessionId: String?) -> Bool {
        let key = approvalTerminalKey(requestId, room: room, sessionId: sessionId)
        guard let markedAt = approvalTerminalTombstones[key] else { return false }
        let nowMs = Date().timeIntervalSince1970 * 1_000
        if nowMs - markedAt <= Self.approvalTombstoneRetentionMs { return true }
        approvalTerminalTombstones[key] = nil
        persistApprovalConvergenceState()
        return false
    }

    func acceptApprovalStatusWatermark(_ generatedAt: Double,
                                               room: String) -> Bool {
        guard generatedAt.isFinite, generatedAt > 0 else {
            append("approvals.status invalid watermark ignored")
            return false
        }
        if let previous = approvalStatusWatermarkByRoom[room], generatedAt <= previous {
            append("approvals.status stale snapshot ignored")
            return false
        }
        approvalStatusWatermarkByRoom[room] = generatedAt
        persistApprovalConvergenceState()
        return true
    }

    /// Called when a room/all links are explicitly removed; keeps persisted
    /// convergence state bounded and prevents a future unrelated link inheriting it.
    func clearApprovalConvergenceState(forRoom room: String? = nil) {
        if let room {
            approvalStatusWatermarkByRoom[room] = nil
            let prefix = "\(room)\u{1f}"
            approvalTerminalTombstones = approvalTerminalTombstones.filter {
                !$0.key.hasPrefix(prefix)
            }
        } else {
            approvalStatusWatermarkByRoom.removeAll()
            approvalTerminalTombstones.removeAll()
        }
        persistApprovalConvergenceState()
    }

    func markDecisionInFlight(_ requestId: String, decision: String,
                                      sessionId: String?) {
        approvalDecisionsInFlight[requestId] = decision
        approvalDecisionSessionScope[requestId] = Self.normalizedApprovalSession(sessionId) ?? ""
    }

    func clearDecisionInFlight(_ requestId: String) {
        approvalDecisionsInFlight[requestId] = nil
        approvalDecisionSessionScope[requestId] = nil
    }
}

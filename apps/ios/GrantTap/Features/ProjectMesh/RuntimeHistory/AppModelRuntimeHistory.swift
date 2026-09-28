import Foundation

@MainActor
extension AppModel {
    static func invocationTaskKey(_ projectId: String, _ taskId: String) -> String {
        "\(projectId)\u{1f}\(taskId)"
    }

    private static func invocationRoomKey(_ taskKey: String, _ room: String) -> String {
        "\(taskKey)\u{1f}\(room)"
    }

    func requestInvocationHistory(projectId: String, taskId: String, older: Bool = false) {
        guard meshSnapshots[projectId]?.tasks.contains(where: { $0.taskId == taskId }) == true
        else { return }
        let taskKey = Self.invocationTaskKey(projectId, taskId)
        #if targetEnvironment(macCatalyst)
        if let reader = localMCPReader, reader.status != nil {
            guard !older, !invocationRequestedTasks.contains(taskKey) else { return }
            invocationRequestedTasks.insert(taskKey)
            Task {
                do {
                    let page = try await reader.invocationHistory(projectId: projectId,
                                                                   taskId: taskId)
                    invocationHistoryByTask[taskKey] = page.records
                    invocationAvailabilityByTask[taskKey] = page.unavailable ? "unavailable" : "ready"
                } catch {
                    invocationAvailabilityByTask[taskKey] = "unavailable"
                    invocationRequestedTasks.remove(taskKey)
                }
            }
            return
        }
        #endif
        guard agentMeshPreferences.meshEnabled else { return }
        if !older && invocationRequestedTasks.contains(taskKey) { return }
        let rooms = meshProjectSourceRooms[projectId] ?? []
        var sent = false
        for room in rooms.sorted() {
            guard let relay = relaysByRoom[room] else { continue }
            let roomKey = Self.invocationRoomKey(taskKey, room)
            let before = older ? invocationOlderCursor[roomKey] : nil
            if older && before == nil { continue }
            if invocationPendingRooms.values.contains(roomKey) { continue }
            let requestId = UUID().uuidString
            if invocationPendingRooms.count >= 64 { break }
            invocationPendingRooms[requestId] = roomKey
            let query = ProjectInvocationQuery(
                type: "mesh.invocation.query", sessionId: projectId,
                projectId: projectId, taskId: taskId,
                requestId: requestId, tail: older ? nil : true,
                beforeSequence: before, afterSequence: nil, limit: 16
            )
            relay.sendSession(payload: query, sessionId: projectId, ttl: 15 * 60)
            sent = true
        }
        if sent && !older { invocationRequestedTasks.insert(taskKey) }
        if !sent && !older && invocationAvailabilityByTask[taskKey] != "ready" {
            invocationAvailabilityByTask[taskKey] = "offline"
        }
    }

    func refreshInvocationHistory(projectId: String, taskId: String) {
        let taskKey = Self.invocationTaskKey(projectId, taskId)
        invocationPendingRooms = invocationPendingRooms.filter {
            !$0.value.hasPrefix("\(taskKey)\u{1f}")
        }
        invocationRequestedTasks.remove(taskKey)
        requestInvocationHistory(projectId: projectId, taskId: taskId)
    }

    func receiveInvocationPage(_ page: ProjectInvocationPage, fromRoom room: String) {
        let taskKey = Self.invocationTaskKey(page.projectId, page.taskId)
        let roomKey = Self.invocationRoomKey(taskKey, room)
        guard page.isWellFormed, invocationPendingRooms[page.requestId] == roomKey,
              meshSnapshots[page.projectId]?.tasks.contains(where: { $0.taskId == page.taskId }) == true
        else { return }
        invocationPendingRooms.removeValue(forKey: page.requestId)
        if page.availability == "ready" || invocationAvailabilityByTask[taskKey] != "ready" {
            invocationAvailabilityByTask[taskKey] = page.availability
        }
        let previous = invocationOlderCursor[roomKey]
        let next = page.hasOlder ? page.previousSequence : nil
        if let previous, let next, next >= previous {
            invocationOlderCursor[roomKey] = nil
        } else {
            invocationOlderCursor[roomKey] = next
        }
        var merged = invocationHistoryByTask[taskKey] ?? []
        var existing = Set(merged.map(\.id))
        for row in page.events {
            let record = ProjectInvocationRecord(room: room, sequence: row.sequence, event: row.event)
            if existing.insert(record.id).inserted { merged.append(record) }
        }
        merged.sort {
            if $0.event.occurred_at != $1.event.occurred_at {
                return $0.event.occurred_at < $1.event.occurred_at
            }
            return $0.id < $1.id
        }
        invocationHistoryByTask[taskKey] = merged
    }

    func hasOlderInvocations(projectId: String, taskId: String) -> Bool {
        let taskKey = Self.invocationTaskKey(projectId, taskId)
        return invocationOlderCursor.keys.contains { $0.hasPrefix("\(taskKey)\u{1f}") }
    }

    func olderInvocationPageKey(projectId: String, taskId: String) -> String {
        let prefix = "\(Self.invocationTaskKey(projectId, taskId))\u{1f}"
        return invocationOlderCursor.filter { $0.key.hasPrefix(prefix) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: "|")
    }
}

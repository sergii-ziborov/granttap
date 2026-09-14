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
        guard agentMeshPreferences.meshEnabled,
              meshSnapshots[projectId]?.tasks.contains(where: { $0.taskId == taskId }) == true
        else { return }
        let taskKey = Self.invocationTaskKey(projectId, taskId)
        if !older && invocationRequestedTasks.contains(taskKey) { return }
        if !older { invocationRequestedTasks.insert(taskKey) }
        let rooms = meshProjectSourceRooms[projectId] ?? []
        var sent = false
        for room in rooms.sorted() {
            guard let relay = relaysByRoom[room] else { continue }
            let roomKey = Self.invocationRoomKey(taskKey, room)
            let before = older ? invocationOlderCursor[roomKey] : nil
            if older && before == nil { continue }
            let requestId = UUID().uuidString
            if invocationPendingRooms.count >= 64 { invocationPendingRooms.removeAll() }
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
        invocationOlderCursor[roomKey] = page.hasOlder ? page.previousSequence : nil
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
        invocationHistoryByTask[taskKey] = Array(merged.suffix(256))
    }

    func hasOlderInvocations(projectId: String, taskId: String) -> Bool {
        let taskKey = Self.invocationTaskKey(projectId, taskId)
        return invocationOlderCursor.keys.contains { $0.hasPrefix("\(taskKey)\u{1f}") }
    }
}

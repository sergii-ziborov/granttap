import Foundation

@MainActor
extension AppModel {
    func receive(_ snapshot: ProjectMeshSnapshot, fromRoom room: String) {
        guard agentMeshPreferences.meshEnabled else { return }
        let now = Date().timeIntervalSince1970 * 1_000
        guard snapshot.sessionId == snapshot.projectId else { return }
        let newSourceRoom = registerCapabilitySource(snapshot: snapshot, room: room)
        meshSnapshots[snapshot.projectId] = withoutReleasedClaims(
            ProjectMeshLogic.merged(
                current: meshSnapshots[snapshot.projectId], incoming: snapshot, nowMs: now
            ),
            at: now
        )
        if let request = projectGraphRequests[snapshot.projectId] {
            projectGraphRequests[snapshot.projectId] = request.receiving(snapshot)
        }
        if sessions.contains(where: { $0.projectId == snapshot.projectId }) {
            ensureProjectGraphAnalysis(projectId: snapshot.projectId)
        }
        if newSourceRoom { flushProjectCapabilityRequests(projectId: snapshot.projectId) }
        for stale in ProjectMeshLogic.staleIdentities(
            in: meshSnapshots, besides: snapshot,
            sourceRooms: meshProjectSourceRooms, incomingRoom: room
        ) {
            meshSnapshots.removeValue(forKey: stale)
            meshProjectSourceRooms.removeValue(forKey: stale)
        }
        persistMeshState()
        forwardProjectSnapshot(snapshot.projectId, excluding: room)
        objectWillChange.send()
    }

    func receive(_ event: ProjectMeshEvent, fromRoom room: String) {
        guard agentMeshPreferences.meshEnabled else { return }
        let now = Date().timeIntervalSince1970 * 1_000
        guard event.sessionId == event.taskId,
              event.expiresAt.map({ $0 > now }) ?? true,
              !containsMeshEvent(event.eventId) else { return }
        if let receipt = event.payload.receipt,
           !ProjectMeshReceiptValidator.valid(
                receipt, for: event, in: meshSnapshots[event.projectId]
           ) { return }
        meshEventSourceRooms[event.eventId] = room
        meshProjectSourceRooms[event.projectId, default: []].insert(room)
        sessionSourceRooms[event.sourceSessionId] = [room]
        let expectedRoute = event.payload.capsule.map {
            Self.handoffRoute(provider: $0.targetProvider, computer: $0.targetComputer)
        }
        let locallyAuthorized = event.eventType == "HANDOFF_REQUEST"
            && authorizedHandoffRoutes[event.taskId] == expectedRoute
        if locallyAuthorized {
            authorizedHandoffRoutes[event.taskId] = nil
            forwardMeshEventIfAddressed(event, fromRoom: room)
        }
        let requiresAuthorization = ProjectMeshLogic.requiresHandoffAuthorization(event, locallyAuthorized: locallyAuthorized)
        var attentionItem: HumanAttentionItem?
        if ProjectMeshLogic.needsHuman(type: event.eventType, payload: event.payload)
            || requiresAuthorization {
            pendingMeshEvents.append(event)
            pendingMeshEvents = Array(pendingMeshEvents.suffix(128))
            meshAttentionStates[event.eventId] = .init(
                status: .pending, createdAt: event.createdAt,
                presentedAt: now, updatedAt: now
            )
            attentionItem = meshAttentionItem(event)
        } else if !locallyAuthorized {
            forwardMeshEventIfAddressed(event, fromRoom: room)
        }
        var summary = event
        summary.payload.transferContext = nil
        mergeMeshEvent(summary, nowMs: now)
        if attentionItem == nil { meshEventSourceRooms[event.eventId] = nil }
        persistMeshState()
        objectWillChange.send()
        if let attentionItem {
            NotificationManager.shared.present(attentionItem, roomId: room)
            pushToWatch()
        }
        finishBackgroundWake(.newData)
    }

    func authorizeMeshEvent(_ eventId: String) {
        guard let event = pendingMeshEvents.first(where: { $0.eventId == eventId }),
              event.eventType == "HANDOFF_REQUEST",
              let sourceRoom = meshEventSourceRooms[eventId]
                ?? sourceRoom(forSessionId: event.sourceSessionId),
              let destination = meshDestinationRoom(event), destination != sourceRoom
        else { return }
        forwardProjectSnapshot(event.projectId, toRoom: destination, sourceRoom: sourceRoom)
        forwardMesh(event, scopeId: event.taskId, purpose: "task",
                    sourceRoom: sourceRoom, targetRoom: destination)
        resolveMeshAttention(eventId, status: .resolved)
    }

    @discardableResult
    func prepareTaskHandoff(
        session: SessionInfo,
        targetProvider: String,
        targetComputer: String,
        targetModel: String? = nil,
        userComment: String? = nil,
        checkpoint: Bool = false,
        push: Bool = false,
        completion: ((Error?) -> Void)? = nil
    ) -> Bool {
        let note = userComment?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard agentMeshPreferences.meshEnabled,
              agentMeshPreferences.isProviderEnabled(targetProvider),
              let projectId = session.projectId, let taskId = session.taskId,
              AgentIdentity.knownIds.contains(targetProvider),
              targetModel.map({ TurnModel(rawValue: $0) != nil }) ?? true,
              note.map({ !$0.isEmpty && $0.count <= 1_000 }) ?? true,
              let source = relayForSession(session.sessionId) else { return false }
        let request = ProjectMeshHandoffPrepare(
            type: "mesh.handoff.prepare",
            sessionId: session.sessionId,
            projectId: projectId,
            taskId: taskId,
            targetProvider: targetProvider,
            targetComputer: targetComputer,
            targetModel: targetModel,
            userComment: note,
            createdAt: Date().timeIntervalSince1970 * 1_000,
            checkpoint: checkpoint ? true : nil,
            push: push ? true : nil, prepareOnly: true
        )
        authorizedHandoffRoutes[taskId] = Self.handoffRoute(
            provider: targetProvider, computer: targetComputer
        )
        source.send(payload: request, ttl: 15 * 60) { [weak self] error in
            Task { @MainActor in
                if error != nil {
                    self?.authorizedHandoffRoutes[taskId] = nil
                    self?.append("handoff preparation failed")
                }
                completion?(error)
            }
        }
        return true
    }

    func prepareTaskHandoff(session: SessionInfo, targetActorId: String) {
        guard agentMeshPreferences.meshEnabled,
              let connection = grokBotConnection,
              connection.credential.status == "active",
              connection.actors.contains(where: { $0.actorId == targetActorId && $0.enabled }),
              let projectId = session.projectId,
              connection.credential.projectIds.contains(projectId),
              let taskId = session.taskId,
              let source = relayForSession(session.sessionId) else { return }
        let request = ProjectMeshHandoffPrepare(
            type: "mesh.handoff.prepare", sessionId: session.sessionId,
            projectId: projectId, taskId: taskId, targetProvider: "grok_bot",
            targetActorId: targetActorId, targetComputer: connection.endpoint.displayName,
            createdAt: Date().timeIntervalSince1970 * 1_000
        )
        authorizedHandoffRoutes[taskId] = Self.handoffRoute(
            provider: "grok_bot", computer: connection.endpoint.displayName
        )
        source.send(payload: request, ttl: 15 * 60) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.authorizedHandoffRoutes[taskId] = nil }
        }
    }

    /// Publish the human's answer to an agent question back to the asking room.
    /// The reply is a scoped Mesh event addressed to its asking execution.
    func answerMeshQuestion(_ eventId: String, text: String) {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard agentMeshPreferences.meshEnabled, !answer.isEmpty, answer.count <= 1_000,
              let question = pendingMeshEvents.first(where: { $0.eventId == eventId }),
              question.eventType == "AGENT_QUESTION",
              let room = meshEventSourceRooms[eventId]
                ?? sourceRoom(forSessionId: question.sourceSessionId),
              let relay = meshRelay(forRoom: room),
              relay.sessionKey(for: question.taskId) != nil else { return }
        let createdAt = Date().timeIntervalSince1970 * 1_000
        let event = ProjectMeshEvent(
            type: "mesh.event", sessionId: question.taskId,
            eventId: "answer-\(UUID().uuidString)", projectId: question.projectId,
            taskId: question.taskId, sourceSessionId: "user:phone",
            targetSessionId: question.sourceSessionId, eventType: "AGENT_ANSWER",
            createdAt: createdAt, expiresAt: createdAt + 24 * 60 * 60_000,
            payload: .init(questionEventId: eventId, answer: answer)
        )
        relay.sendSession(payload: event, sessionId: question.taskId, ttl: 24 * 60 * 60)
        mergeMeshEvent(event, nowMs: createdAt)
        resolveMeshAttention(eventId, status: .answered)
        objectWillChange.send()
    }

    func meshEvents(forTaskId taskId: String?) -> [ProjectMeshEvent] {
        guard let taskId else { return [] }
        return taskMeshEventIndex.events(for: taskId, revision: transcriptRevision, snapshots: meshSnapshots)
    }

    func meshSnapshot(for projectId: String?) -> ProjectMeshSnapshot? {
        projectId.flatMap { meshSnapshots[$0] }
    }

    func mergeMeshEvent(_ event: ProjectMeshEvent, nowMs: Double) {
        guard var snapshot = meshSnapshots[event.projectId] else { return }
        let known = snapshot.events
        snapshot.events = ProjectMeshLogic.compactEvents(known + [event], nowMs: nowMs)
        if event.eventType == "TASK_COMPLETED",
           let index = snapshot.executions.firstIndex(where: {
               $0.taskId == event.taskId && $0.sessionId == event.sourceSessionId
           }) {
            snapshot.executions[index].state = "idle"
            snapshot.executions[index].updatedAt = max(snapshot.executions[index].updatedAt ?? 0, event.createdAt)
        }
        snapshot.tasks = snapshot.tasks.map { task in
            guard task.taskId == event.taskId else { return task }
            return ProjectMeshConvergence.task(after: event, task: task, knownEvents: known,
                                               executions: snapshot.executions) ?? task
        }
        meshSnapshots[event.projectId] = snapshot
    }

    private func containsMeshEvent(_ eventId: String) -> Bool {
        pendingMeshEvents.contains { $0.eventId == eventId }
            || meshSnapshots.values.contains { $0.events.contains { $0.eventId == eventId } }
    }

    private func meshDestinationRoom(_ event: ProjectMeshEvent) -> String? {
        if event.payload.capsule?.targetProvider == "grok_bot",
           let actorId = event.payload.capsule?.targetActorId,
           let connection = grokBotConnection,
           connection.credential.status == "active",
           connection.actors.contains(where: { $0.actorId == actorId && $0.enabled }) {
            return connection.phonePairing.room
        }
        var sessionRooms: [String: String] = [:]
        for (sessionId, rooms) in sessionSourceRooms where rooms.count == 1 {
            sessionRooms[sessionId] = rooms[0]
        }
        var computerRooms: [String: String] = [:]
        for connection in connectionRegistry.connections {
            let published = connection.lastMachineName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !published.isEmpty { computerRooms[published] = connection.id }
            computerRooms[connection.displayName] = connection.id
        }
        return ProjectMeshLogic.destinationRoom(
            for: event, sessionRooms: sessionRooms, computerRooms: computerRooms
        )
    }

    private func forwardMeshEventIfAddressed(_ event: ProjectMeshEvent, fromRoom room: String) {
        guard let destination = meshDestinationRoom(event), destination != room else { return }
        forwardMesh(event, scopeId: event.taskId, purpose: "task",
                    sourceRoom: room, targetRoom: destination)
    }

    private func forwardProjectSnapshot(_ projectId: String, excluding room: String) {
        for destination in meshProjectSourceRooms[projectId] ?? [] where destination != room {
            forwardProjectSnapshot(projectId, toRoom: destination, sourceRoom: room)
        }
    }

    private func forwardProjectSnapshot(_ projectId: String, toRoom: String, sourceRoom: String) {
        guard let snapshot = meshSnapshots[projectId] else { return }
        forwardMesh(snapshot, scopeId: projectId, purpose: "project",
                    sourceRoom: sourceRoom, targetRoom: toRoom)
    }

    func persistMeshState() {
        let pendingIds = Set(pendingMeshEvents.map(\.eventId))
        let retainedStates = meshAttentionStates.filter { eventId, state in
            pendingIds.contains(eventId) || isTerminalAttentionState(state.status)
        }.sorted { lhs, rhs in
            let left = lhs.value.updatedAt ?? lhs.value.createdAt ?? 0
            let right = rhs.value.updatedAt ?? rhs.value.createdAt ?? 0
            return left == right ? lhs.key < rhs.key : left > right
        }.prefix(256)
        let boundedStates = Dictionary(uniqueKeysWithValues: retainedStates.map {
            ($0.key, $0.value)
        })
        if meshAttentionStates != boundedStates { meshAttentionStates = boundedStates }
        ProjectMeshPersistence.save(ProjectMeshArchive(
            snapshots: meshSnapshots,
            pendingEvents: pendingMeshEvents,
            eventSourceRooms: meshEventSourceRooms.filter { pendingIds.contains($0.key) },
            attentionStates: boundedStates,
            projectRooms: meshProjectSourceRooms.mapValues { Array($0).sorted() }
        ))
    }

    private func isTerminalAttentionState(_ status: ProjectMeshAttentionStatus) -> Bool {
        switch status {
        case .answered, .declined, .acknowledged, .resolved: return true
        case .pending, .snoozed: return false
        }
    }

}

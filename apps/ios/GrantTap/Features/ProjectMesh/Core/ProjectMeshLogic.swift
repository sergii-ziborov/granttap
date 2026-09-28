import Foundation

enum ProjectMeshLogic {
    static func needsHuman(type: String, payload: ProjectMeshEventPayload) -> Bool {
        switch type {
        case "AGENT_QUESTION":
            return ["product", "business", "security", "destructive"].contains(payload.category ?? "")
        case "CONFLICT":
            return payload.resolved != true && payload.needsUser == true
        case "TASK_BLOCKED":
            return payload.needsUser == true
        case "HANDOFF_REJECTED":
            return payload.failed == true
        default:
            return false
        }
    }

    static func visibleProject(_ snapshot: ProjectMeshSnapshot) -> Bool {
        snapshot.tasks.count >= 2 || snapshot.executions.count >= 2
    }

    static func destinationRoom(
        for event: ProjectMeshEvent,
        sessionRooms: [String: String],
        computerRooms: [String: String]
    ) -> String? {
        if let target = event.targetSessionId, let room = sessionRooms[target] { return room }
        if let computer = event.payload.capsule?.targetComputer {
            return computerRooms[computer]
        }
        return nil
    }

    static func compactEvents(_ events: [ProjectMeshEvent], nowMs: Double) -> [ProjectMeshEvent] {
        var byId: [String: ProjectMeshEvent] = [:]
        for event in events where event.expiresAt.map({ $0 > nowMs }) ?? true {
            byId[event.eventId] = event
        }
        return Array(byId.values.sorted { $0.createdAt < $1.createdAt }.suffix(128))
    }

    static func merged(
        current: ProjectMeshSnapshot?, incoming: ProjectMeshSnapshot, nowMs: Double
    ) -> ProjectMeshSnapshot {
        guard let current else {
            var clean = incoming
            clean.events = compactEvents(incoming.events, nowMs: nowMs)
            clean.claims = incoming.claims.filter { $0.expiresAt > nowMs }
            return rejoinSplitChats(clean)
        }
        var merged = incoming.generatedAt >= current.generatedAt ? incoming : current
        merged.tasks = merge(current.tasks, incoming.tasks, key: \.taskId,
                             prefer: ProjectMeshConvergence.preferred)
        merged.executions = merge(current.executions, incoming.executions, key: \.id,
                                  prefer: ProjectMeshConvergence.preferred)
        merged.claims = merge(current.claims, incoming.claims, key: \.claimId)
            .filter { $0.expiresAt > nowMs }
        merged.dependencies = merge(current.dependencies, incoming.dependencies, key: \.id)
        let bindings = merge(current.bindings ?? [], incoming.bindings ?? [], key: \.bindingId)
        merged.bindings = bindings.isEmpty ? nil : bindings
        // Each computer publishes the map of its own checkouts; the Project's
        // map is their union, kept absent while nobody states an edge.
        let peers = merge(current.peers ?? [], incoming.peers ?? [], key: \.id)
        merged.peers = peers.isEmpty ? nil : peers
        ProjectMeshCapabilityMerge.merge(into: &merged, current: current, incoming: incoming)
        if current.publisherEndpointId != incoming.publisherEndpointId {
            // This cached view now combines reports from several computers.
            merged.publisherEndpointId = nil
        }
        let catalogs = merge(current.modelCatalog ?? [], incoming.modelCatalog ?? [], key: \.endpointId) {
            $1.observedAt >= $0.observedAt ? $1 : $0
        }
        merged.modelCatalog = catalogs.isEmpty ? nil : catalogs
        merged.backbone = incoming.backbone ?? current.backbone
        let graphs = merge(current.repositoryGraphs ?? [], incoming.repositoryGraphs ?? [],
                           key: \.repositoryId) { old, new in
            incoming.generatedAt >= current.generatedAt ? new : old
        }
        merged.repositoryGraphs = graphs.isEmpty ? nil : graphs
        let cortex = merge(current.cortex ?? [], incoming.cortex ?? [], key: \.endpointId) {
            $1.checkedAt >= $0.checkedAt ? $1 : $0
        }
        merged.cortex = cortex.isEmpty ? nil : cortex
        ProjectMeshKnowledgeMerge.merge(into: &merged, current: current, incoming: incoming)
        merged.incomplete = current.incomplete == true || incoming.incomplete == true
        merged.execution = ProjectMeshRevisionPreference.newest(current.execution, incoming.execution, revision: \.revision)
        merged.restrictions = ProjectMeshRevisionPreference.newest(current.restrictions, incoming.restrictions, revision: \.revision)
        merged.environment = ProjectMeshRevisionPreference.newest(current.environment, incoming.environment, revision: \.revision)
        merged.events = compactEvents(current.events + incoming.events, nowMs: nowMs)
        return rejoinSplitChats(merged)
    }

    /// Rejoin a chat that arrived as two Tasks.
    ///
    /// Tasks are merged by id and never removed, so a Task the computer has
    /// stopped publishing stays here for good. That is right for a Task the
    /// phone simply has not heard about lately, and wrong for one that should
    /// never have existed: a Task used to be identified by computer as well as
    /// by chat, so a machine renamed by its network — or a chat read from a
    /// second machine — produced a second Task for one conversation, and the
    /// list showed it twice with two frozen summaries.
    ///
    /// A native id identifies a conversation only inside one Project, provider,
    /// endpoint and workspace. An unscoped owner may join it only when that scope is
    /// unique. The oldest survivor keeps the Task's stable identity.
    private static func rewritesForSplitChats(_ snapshot: ProjectMeshSnapshot) -> [String: String] {
        let taskById = Dictionary(
            snapshot.tasks.map { ($0.taskId, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let ambiguousIds = Set(Dictionary(grouping: snapshot.tasks, by: \.taskId)
            .filter { $0.value.count > 1 }.map(\.key))
        var winnerByChat: [String: String] = [:]
        var rewritten: [String: String] = [:]
        var scopesByOwner: [String: Set<String>] = [:]

        func claim(_ chat: String, for taskId: String) {
            guard let held = winnerByChat[chat] else {
                winnerByChat[chat] = taskId
                return
            }
            guard held != taskId, let left = taskById[held], let right = taskById[taskId]
            else { return }
            let keep = left.createdAt <= right.createdAt ? left : right
            let drop = keep.taskId == left.taskId ? right : left
            winnerByChat[chat] = keep.taskId
            rewritten[drop.taskId] = keep.taskId
        }

        for execution in snapshot.executions.sorted(by: { $0.startedAt < $1.startedAt }) {
            guard !ambiguousIds.contains(execution.taskId), let task = taskById[execution.taskId],
                  task.projectId == snapshot.projectId else { continue }
            let scope = [task.projectId, execution.provider, execution.computerId,
                         execution.workspace, execution.sessionId]
                .joined(separator: "\u{1f}")
            let owner = [task.projectId, execution.sessionId].joined(separator: "\u{1f}")
            scopesByOwner[owner, default: []].insert(scope)
            claim(scope, for: execution.taskId)
        }
        for task in snapshot.tasks.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard !ambiguousIds.contains(task.taskId), task.projectId == snapshot.projectId,
                  let owner = task.ownerSessionId else { continue }
            let key = [task.projectId, owner].joined(separator: "\u{1f}")
            if let scopes = scopesByOwner[key], scopes.count == 1, let scope = scopes.first {
                claim(scope, for: task.taskId)
            }
        }
        return rewritten
    }

    /// Every name of a Task moved at once: the rows that point at it, the
    /// dependencies between two that may both have moved, and the events that
    /// name it inside what they carry.
    static func rejoinSplitChats(_ snapshot: ProjectMeshSnapshot) -> ProjectMeshSnapshot {
        let rewritten = rewritesForSplitChats(snapshot)
        guard !rewritten.isEmpty else { return snapshot }

        // A Task chosen as a winner early can be dropped later, so a rewrite
        // has to be followed to its end rather than applied once.
        func target(_ taskId: String) -> String {
            var current = taskId
            var guardCount = 0
            while let next = rewritten[current], next != current, guardCount < snapshot.tasks.count {
                current = next
                guardCount += 1
            }
            return current
        }
        var joined = snapshot
        joined.tasks = snapshot.tasks.filter { target($0.taskId) == $0.taskId }
        joined.executions = snapshot.executions.map {
            var item = $0
            item.taskId = target(item.taskId)
            return item
        }
        joined.claims = snapshot.claims.map {
            var item = $0
            item.taskId = target(item.taskId)
            return item
        }
        // A dependency names two Tasks, and both may have moved; two that
        // became one are no dependency at all.
        var dependencies: [String: ProjectTaskDependency] = [:]
        var order: [String] = []
        for item in snapshot.dependencies {
            let next = ProjectTaskDependency(
                taskId: target(item.taskId), dependsOnTaskId: target(item.dependsOnTaskId),
                summary: item.summary, createdAt: item.createdAt
            )
            guard next.taskId != next.dependsOnTaskId else { continue }
            if dependencies[next.id] == nil { order.append(next.id) }
            dependencies[next.id] = next
        }
        joined.dependencies = order.compactMap { dependencies[$0] }
        joined.events = rescopedEvents(snapshot.events, target: target)
        return joined
    }

    /// The events of a rejoined Task.
    ///
    /// An event names its Task more than once — as the scope it was published
    /// in and inside what it carries — and every name moves together, the way
    /// the computers move them. A capsule is named by its hash and its Task id
    /// is part of it, so a receipt that named the old hash names the new one.
    private static func rescopedEvents(
        _ events: [ProjectMeshEvent], target: (String) -> String
    ) -> [ProjectMeshEvent] {
        var rehashed: [String: String] = [:]
        let rescoped = events.map { event -> ProjectMeshEvent in
            let next = rescopedEvent(event, target: target)
            if let before = event.payload.capsule, let after = next.payload.capsule, event.taskId != next.taskId,
               let from = ProjectMeshReceiptValidator.capsuleHash(before),
               let to = ProjectMeshReceiptValidator.capsuleHash(after) {
                rehashed[from] = to
            }
            return next
        }
        return rescoped.map { event in
            guard let receipt = event.payload.receipt, let to = rehashed[receipt.capsuleHash.lowercased()] else { return event }
            var payload = event.payload
            payload.receipt = ProjectHandoffReceipt(
                sourceSessionId: receipt.sourceSessionId, sourceActorId: receipt.sourceActorId,
                targetSessionId: receipt.targetSessionId, taskId: receipt.taskId, capsuleHash: to, acceptedAt: receipt.acceptedAt
            )
            return withPayload(event, payload)
        }
    }

    private static func rescopedEvent(_ event: ProjectMeshEvent, target: (String) -> String) -> ProjectMeshEvent {
        let taskId = target(event.taskId)
        var payload = event.payload
        if let claim = payload.claim {
            var next = claim
            next.taskId = target(claim.taskId)
            payload.claim = next
        }
        if let receipt = payload.receipt {
            payload.receipt = ProjectHandoffReceipt(
                sourceSessionId: receipt.sourceSessionId, sourceActorId: receipt.sourceActorId,
                targetSessionId: receipt.targetSessionId, taskId: target(receipt.taskId),
                capsuleHash: receipt.capsuleHash, acceptedAt: receipt.acceptedAt
            )
        }
        if let capsule = payload.capsule {
            var seen: Set<String> = []
            let dependencies = capsule.dependencies.map(target).filter { seen.insert($0).inserted && $0 != taskId }
            payload.capsule = TaskCapsule(
                taskId: target(capsule.taskId), goal: capsule.goal, currentStatus: capsule.currentStatus,
                sourceProvider: capsule.sourceProvider, sourceActorId: capsule.sourceActorId,
                sourceComputer: capsule.sourceComputer, targetProvider: capsule.targetProvider,
                targetActorId: capsule.targetActorId, targetComputer: capsule.targetComputer,
                repository: capsule.repository, baseSha: capsule.baseSha, branch: capsule.branch,
                latestCommit: capsule.latestCommit, dirtyDiffHash: capsule.dirtyDiffHash,
                workingTree: capsule.workingTree, filesChanged: capsule.filesChanged, testsStatus: capsule.testsStatus,
                dependencies: dependencies, resourceClaims: capsule.resourceClaims,
                remainingWork: capsule.remainingWork, importantDecisions: capsule.importantDecisions,
                checkpoint: capsule.checkpoint, createdAt: capsule.createdAt
            )
        }
        if let dependsOn = payload.dependsOnTaskId { payload.dependsOnTaskId = target(dependsOn) }
        return ProjectMeshEvent(
            type: event.type, sessionId: taskId, eventId: event.eventId, projectId: event.projectId, taskId: taskId,
            sourceSessionId: event.sourceSessionId, sourceActorId: event.sourceActorId,
            targetSessionId: event.targetSessionId, eventType: event.eventType, createdAt: event.createdAt,
            expiresAt: event.expiresAt, payload: payload
        )
    }

    private static func withPayload(_ event: ProjectMeshEvent, _ payload: ProjectMeshEventPayload) -> ProjectMeshEvent {
        ProjectMeshEvent(
            type: event.type, sessionId: event.sessionId, eventId: event.eventId, projectId: event.projectId,
            taskId: event.taskId, sourceSessionId: event.sourceSessionId, sourceActorId: event.sourceActorId,
            targetSessionId: event.targetSessionId, eventType: event.eventType, createdAt: event.createdAt,
            expiresAt: event.expiresAt, payload: payload
        )
    }

    /// Without a `prefer` rule the later array simply wins, which is only safe
    /// for entities a late copy cannot make wrong.
    /// A binding retired under a computer's former name is that computer's
    /// leftover, not a second computer: while the same repository is offered
    /// by an available binding, the unavailable twin is not listed.
    static func visibleBindings(_ bindings: [ProjectBindingSummary]) -> [ProjectBindingSummary] {
        let offered = Set(bindings.filter(\.available).map(\.repositoryId))
        return bindings.filter { $0.available || !offered.contains($0.repositoryId) }
    }

    private static func merge<T, Key: Hashable>(
        _ first: [T], _ second: [T], key: KeyPath<T, Key>,
        prefer: (T, T) -> T = { _, incoming in incoming }
    ) -> [T] {
        var values: [Key: T] = [:]
        for item in first + second {
            let id = item[keyPath: key]
            values[id] = values[id].map { prefer($0, item) } ?? item
        }
        return Array(values.values)
    }
}

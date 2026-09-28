import Foundation

enum ProjectGraphTopology {
    /// Repository rows need edges and names, not every graph tower and layer.
    static func repositoryMap(_ snapshot: ProjectMeshSnapshot) -> (names: [String: String], edges: [ProjectGraphEdge]) {
        let own = snapshot.project.canonicalRepositoryId
        var names = repositoryNames(snapshot, bindings: snapshot.bindings ?? [])
        let owners = backboneOwners(snapshot.backbone, repositoryNames: &names, own: own)
        let edges = topologyEdges(snapshot, owners: owners, names: &names)
        return (names, edges)
    }

    static func make(_ snapshot: ProjectMeshSnapshot) -> ProjectGraphModel {
        let own = snapshot.project.canonicalRepositoryId
        let bindings = snapshot.bindings ?? []
        var names = repositoryNames(snapshot, bindings: bindings)
        let owners = backboneOwners(snapshot.backbone, repositoryNames: &names, own: own)
        let edges = topologyEdges(snapshot, owners: owners, names: &names)
        let entities = entityLayers(snapshot, owners: owners, own: own)
        let nodes = names.map { id, name in
            tower(id: id, name: name, own: own, snapshot: snapshot,
                  entities: entities[id] ?? [])
        }.sorted { $0.isOwn == $1.isOwn ? $0.name < $1.name : $0.isOwn }
        return ProjectGraphModel(nodes: nodes, edges: edges.sorted { $0.id < $1.id })
    }

    private static func repositoryNames(
        _ snapshot: ProjectMeshSnapshot, bindings: [ProjectBindingSummary]
    ) -> [String: String] {
        let own = snapshot.project.canonicalRepositoryId
        var names = [own: ProjectOtherSide.displayName(of: own, in: snapshot)]
        for binding in bindings where names[binding.repositoryId] == nil {
            names[binding.repositoryId] = binding.displayName.nilIfBlank
                ?? ProjectOtherSide.displayName(of: binding.repositoryId, in: snapshot)
        }
        for execution in snapshot.executions {
            guard let id = execution.repositoryId, names[id] == nil else { continue }
            names[id] = ProjectOtherSide.displayName(of: id, in: snapshot)
        }
        return names
    }

    private static func backboneOwners(
        _ backbone: ProjectBackbone?, repositoryNames names: inout [String: String], own: String
    ) -> [String: String] {
        guard let backbone else { return [:] }
        var owners: [String: String] = [:]
        for node in backbone.nodes where node.kind == "repository" {
            let repository = matchedRepository(node, names: names) ?? node.identity
            if names[repository] == nil { names[repository] = node.displayName }
            owners[node.identity] = repository
        }
        for _ in 0..<3 {
            for relation in backbone.relations where relation.relation == "owns" {
                if let source = owners[relation.source] { owners[relation.target] = source }
            }
        }
        for node in backbone.nodes where owners[node.identity] == nil { owners[node.identity] = own }
        return owners
    }

    private static func matchedRepository(
        _ node: ProjectBackboneNode, names: [String: String]
    ) -> String? {
        names[node.identity] == nil ? nil : node.identity
    }

    private static func topologyEdges(
        _ snapshot: ProjectMeshSnapshot, owners: [String: String], names: inout [String: String]
    ) -> [ProjectGraphEdge] {
        if snapshot.backbone?.relations.isEmpty == false {
            return backboneEdges(snapshot.backbone, owners: owners)
        }
        return compatibilityEdges(snapshot, names: &names)
    }

    private static func backboneEdges(
        _ backbone: ProjectBackbone?, owners: [String: String]
    ) -> [ProjectGraphEdge] {
        var seen = Set<String>()
        return (backbone?.relations ?? []).compactMap { relation in
            guard let source = owners[relation.source], let target = owners[relation.target],
                  source != target else { return nil }
            let edge = ProjectGraphEdge(
                source: source, target: target, relation: relation.relation,
                through: "\(relation.evidenceCount) evidence"
            )
            return seen.insert(edge.id).inserted ? edge : nil
        }
    }

    private static func compatibilityEdges(
        _ snapshot: ProjectMeshSnapshot, names: inout [String: String]
    ) -> [ProjectGraphEdge] {
        let bindings = snapshot.bindings ?? []
        var seen = Set<String>()
        return (snapshot.peers ?? []).compactMap { peer in
            if names[peer.repositoryId] == nil {
                names[peer.repositoryId] = ProjectOtherSide.displayName(of: peer.repositoryId, in: snapshot)
            }
            let target = bindingId(named: peer.peer, in: bindings) ?? "peer:\(normalized(peer.peer))"
            if names[target] == nil { names[target] = peer.peer }
            let edge = ProjectGraphEdge(
                source: peer.repositoryId, target: target,
                relation: peer.relation, through: peer.through
            )
            return seen.insert(edge.id).inserted ? edge : nil
        }
    }

    private static func entityLayers(
        _ snapshot: ProjectMeshSnapshot, owners: [String: String], own: String
    ) -> [String: [ProjectGraphLayer]] {
        var result: [String: [ProjectGraphLayer]] = [:]
        for graph in snapshot.repositoryGraphs ?? [] {
            result[graph.repositoryId, default: []] += graph.nodes
                .filter { $0.kind != "repository" }
                .map { .init(id: "weavatrix:\($0.id)", label: $0.label, kind: .entity) }
        }
        for node in snapshot.backbone?.nodes ?? [] where node.kind != "repository" {
            let repository = owners[node.identity] ?? own
            if result[repository]?.contains(where: { $0.label == node.displayName }) != true {
                result[repository, default: []].append(.init(
                    id: "entity:\(node.identity)", label: node.displayName, kind: .entity
                ))
            }
        }
        return result.mapValues { Array($0.sorted { $0.label < $1.label }.prefix(18)) }
    }

    private static func tower(
        id: String, name: String, own: String, snapshot: ProjectMeshSnapshot,
        entities: [ProjectGraphLayer]
    ) -> ProjectGraphNode {
        let bindings = snapshot.bindings ?? []
        let bound = bindings.filter { $0.repositoryId == id }
        let taskIds = activeTaskIds(repositoryId: id, own: own, snapshot: snapshot)
        let computers = bound.sorted { $0.displayName < $1.displayName }.map {
            ProjectGraphLayer(id: $0.bindingId, label: $0.displayName, kind: .computer)
        }
        let tasks = snapshot.tasks.filter { taskIds.contains($0.taskId) }
            .sorted { $0.updatedAt > $1.updatedAt }.prefix(12)
            .map { ProjectGraphLayer(id: $0.taskId, label: $0.title, kind: .task) }
        let extra = id == own ? capabilityLayers(snapshot) : []
        let layers = [ProjectGraphLayer(id: id, label: name, kind: .repository)]
            + computers + entities + extra + tasks
        return .init(id: id, name: name, isOwn: id == own,
                     available: id == own || bound.contains { $0.available },
                     openTasks: taskIds.count, layers: layers)
    }

    private static func activeTaskIds(
        repositoryId: String, own: String, snapshot: ProjectMeshSnapshot
    ) -> Set<String> {
        Set(snapshot.executions.filter {
            ($0.repositoryId == repositoryId || (repositoryId == own && $0.repositoryId == nil))
                && $0.endedAt == nil
        }.map(\.taskId))
    }

    private static func capabilityLayers(_ snapshot: ProjectMeshSnapshot) -> [ProjectGraphLayer] {
        let skills = (snapshot.skills ?? []).prefix(6).map {
            ProjectGraphLayer(id: "skill:\($0.name)", label: $0.name, kind: .skill)
        }
        let mcp = (snapshot.mcpServers ?? []).prefix(6).map {
            ProjectGraphLayer(id: "mcp:\($0.id)", label: $0.title ?? $0.name, kind: .mcp)
        }
        let models = (snapshot.modelCatalog ?? []).flatMap(\.models).prefix(6).map {
            ProjectGraphLayer(id: "model:\($0.id)", label: $0.label ?? $0.modelId, kind: .model)
        }
        let cortex = (snapshot.cortex ?? []).prefix(6).map {
            let label = $0.version.map { "Cortex \($0)" } ?? "Cortex Loom"
            return ProjectGraphLayer(id: "cortex:\($0.endpointId)", label: label, kind: .cortex)
        }
        return skills + mcp + models + cortex
    }

    private static func bindingId(named name: String, in bindings: [ProjectBindingSummary]) -> String? {
        let wanted = normalized(name)
        return bindings.first { ProjectOtherSide.repositoryNames($0).contains(wanted) }?.repositoryId
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

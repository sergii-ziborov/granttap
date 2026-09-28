import Foundation

struct ProjectGraphNode: Identifiable, Equatable {
    let id: String
    let name: String
    let isOwn: Bool
    let available: Bool
    let openTasks: Int
    let layers: [ProjectGraphLayer]
}

struct ProjectGraphLayer: Identifiable, Equatable {
    enum Kind: Equatable { case repository, computer, task, skill, mcp, model, entity, cortex }
    let id: String
    let label: String
    let kind: Kind
}

struct ProjectGraphEdge: Identifiable, Equatable {
    let source: String
    let target: String
    let relation: String
    let through: String?
    var id: String { [source, target, relation, through ?? ""].joined(separator: "\u{1f}") }
}

struct ProjectGraphModel: Equatable {
    let nodes: [ProjectGraphNode]
    let edges: [ProjectGraphEdge]

    static func make(from snapshot: ProjectMeshSnapshot) -> ProjectGraphModel {
        ProjectGraphTopology.make(snapshot)
    }
}

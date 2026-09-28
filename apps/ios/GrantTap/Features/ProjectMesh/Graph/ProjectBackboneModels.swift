import Foundation

struct ProjectBackboneNode: Codable, Equatable, Identifiable {
    let kind: String
    let identity: String
    let displayName: String
    var id: String { identity }
}

struct ProjectBackboneRelation: Codable, Equatable, Identifiable {
    let source: String
    let target: String
    let relation: String
    let evidenceCount: Int
    var id: String { "\(source):\(relation):\(target)" }
}

struct ProjectBackbone: Codable, Equatable {
    let projectId: String
    var head: String? = nil
    let nodes: [ProjectBackboneNode]
    let relations: [ProjectBackboneRelation]
    let pendingCandidateCount: Int
}

struct ProjectRepositoryGraph: Codable, Equatable, Identifiable {
    struct ArchitectureHypothesis: Codable, Equatable, Identifiable {
        let name: String
        let dimension: String
        let status: String
        let evidence: [String]
        let contradictions: [String]
        let unknowns: [String]
        var id: String { name }
    }

    struct Node: Codable, Equatable, Identifiable {
        let id: String
        let kind: String
        let label: String
    }

    struct Relation: Codable, Equatable, Identifiable {
        let source: String
        let target: String
        let relation: String
        var evidenceCount: Int? = nil
        var id: String { "\(source):\(relation):\(target)" }
    }

    let projectId: String
    let repositoryId: String
    let revision: String
    let weavatrixVersion: String
    var analysisId: String? = nil
    var analysisStatus: String? = nil
    var analysisErrorCode: String? = nil
    var architectureHypotheses: [ArchitectureHypothesis]? = nil
    var codeMap: ProjectCodeMap? = nil
    let nodes: [Node]
    let relations: [Relation]
    let totalNodes: Int
    let totalRelations: Int
    let truncated: Bool
    var id: String { repositoryId }
}

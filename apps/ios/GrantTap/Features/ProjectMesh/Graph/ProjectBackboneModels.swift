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
    var sourceRevision: String? = nil
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

extension ProjectRepositoryGraph {
    /// Why a computer has no Graph for a repository, in words a person can act on.
    static func unavailableReason(_ code: String?) -> String {
        switch code {
        case "ENGINE_ADMISSION_UNAVAILABLE":
            return L("The computer's project engine has not accepted this checkout yet. It retries on its next refresh.")
        case "REPOSITORY_IDENTITY_MISMATCH":
            return L("This Mesh's saved checkout now belongs to another repository. Review its computer binding.")
        case "REPOSITORY_IDENTITY_UNVERIFIED":
            return L("The bound checkout's repository identity could not be verified.")
        case "REPOSITORY_NOT_BOUND":
            return L("This computer did not verify a Mesh binding for this repository. Build architecture now to refresh its bindings and retry.")
        case "REPOSITORY_NOT_LOCAL", "WEAVATRIX_REPOSITORY_REQUIRED":
            return L("No local Git checkout is available for architecture analysis on this computer.")
        default:
            return L("Architecture analysis is unavailable on this computer.")
        }
    }
}

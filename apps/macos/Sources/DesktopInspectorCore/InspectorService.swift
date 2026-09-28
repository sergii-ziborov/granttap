import Foundation

public struct EngineVersion: Decodable, Sendable {
    public let engine_version: String
    public let cortex_version: String
    public let cortex_revision: String
    public let weavatrix_version: String
}

public struct InspectorProject: Decodable, Sendable, Identifiable {
    public let project_id: String
    public let name: String
    public let created_at: Double
    public var id: String { project_id }
}

public struct InspectorProjectPage: Decodable, Sendable {
    public let projects: [InspectorProject]
    public let next_after_project_id: String?
}

public struct InspectorBinding: Decodable, Sendable, Identifiable {
    public let binding_id: String
    public let repository_id: String
    public let endpoint_id: String
    public let role: String
    public let local_alias: String?
    public let observed_revision: String?
    public var id: String { binding_id }
}

public struct InspectorPolicy: Decodable, Sendable {
    public struct Rule: Decodable, Sendable, Identifiable {
        public let rule_id: String
        public let effect: String
        public var id: String { rule_id }
    }
    public let revision: Int
    public let enforcement: String
    public let rules: [Rule]
}

public struct InspectorBackbone: Decodable, Sendable {
    public struct Node: Decodable, Sendable, Identifiable {
        public let kind: String
        public let identity: String
        public let display_name: String
        public var id: String { identity }
    }
    public struct Relation: Decodable, Sendable, Identifiable {
        public let source: String
        public let target: String
        public let relation: String
        public let evidence_count: Int
        public var id: String { "\(source):\(relation):\(target)" }
    }
    public let head: String?
    public let nodes: [Node]
    public let relations: [Relation]
    public let pending_candidate_count: Int
}

public struct InspectorSnapshot: Sendable {
    public let version: EngineVersion
    public let sourceSocketPath: String
    public let project: InspectorProject?
    public let taskId: String?
    public let bindings: [InspectorBinding]
    public let policy: InspectorPolicy?
    public let coverage: InspectorPolicyCoverage?
    public let backbone: InspectorBackbone?
    public var knowledge: InspectorKnowledgePage?
    public var invocations: InspectorInvocationPage?
}

public struct InspectorService: Sendable {
    private let client: EngineClient

    public init(client: EngineClient) { self.client = client }

    public func resolveProject(localRoot: String) throws -> String {
        try decode(ResolutionReply.self, .resolveFolder(localRoot)).resolution.project_id
    }

    public func projectPage(afterProjectId: String? = nil) throws -> InspectorProjectPage {
        try decode(ProjectCatalogReply.self, .projects(afterProjectId: afterProjectId)).page
    }

    public func meshProject(projectId: String) throws -> MeshProjectSnapshot {
        try decode(MeshProjectSnapshot.self, .meshProject(projectId))
    }

    public func workspaceSummary() throws -> MeshWorkspaceSummary {
        try decode(MeshWorkspaceSummary.self, .workspace)
    }

    public func taskActivity(projectId: String, taskId: String) throws -> TaskActivitySnapshot {
        try decode(TaskActivitySnapshot.self,
                   .taskActivity(projectId: projectId, taskId: taskId))
    }

    public func load(projectId: String?, taskId: String? = nil) throws -> InspectorSnapshot {
        let version = try decode(EngineVersion.self, .version)
        guard let projectId, !projectId.isEmpty else {
            return InspectorSnapshot(version: version, sourceSocketPath: client.socketPath,
                                     project: nil, taskId: nil,
                                     bindings: [], policy: nil, coverage: nil, backbone: nil,
                                     knowledge: nil, invocations: nil)
        }
        let project = try decode(ProjectReply.self, .project(projectId)).project
        let bindings = try decode(BindingsReply.self, .bindings(projectId)).bindings
        let policy = try decode(PolicyReply.self, .policy(projectId)).policy
        let reportedCoverage = try? decode(CoverageReply.self, .coverage(projectId)).coverage
        let coverage = reportedCoverage.flatMap { report in
            report.policy_revision == UInt64(exactly: policy.revision)
                && report.enforcement == policy.enforcement ? report : nil
        }
        let backbone = try? decode(BackboneReply.self, .backbone(projectId)).backbone
        let knowledge = try? knowledgePage(projectId: projectId, taskId: taskId)
        let invocations = try? invocationPage(projectId: projectId, taskId: taskId)
        return InspectorSnapshot(version: version, sourceSocketPath: client.socketPath,
                                 project: project, taskId: taskId,
                                 bindings: bindings, policy: policy, coverage: coverage,
                                 backbone: backbone,
                                 knowledge: knowledge, invocations: invocations)
    }

    public func knowledgePage(projectId: String, taskId: String? = nil,
                              beforeVersion: UInt64? = nil) throws -> InspectorKnowledgePage {
        try decode(KnowledgeReply.self, .knowledge(projectId: projectId, taskId: taskId,
                                                   beforeVersion: beforeVersion)).page
    }

    public func invocationPage(projectId: String, taskId: String? = nil,
                               beforeSequence: UInt64? = nil) throws -> InspectorInvocationPage {
        try decode(InvocationReply.self, .invocations(projectId: projectId, taskId: taskId,
                                                       beforeSequence: beforeSequence)).page
    }

    private func decode<T: Decodable>(_ type: T.Type, _ query: EngineQuery) throws -> T {
        let result = try client.request(query)
        do { return try JSONDecoder().decode(type, from: result) }
        catch { throw EngineClientError.incompatibleResponse }
    }
}

private struct ProjectReply: Decodable { let project: InspectorProject }
private struct ProjectCatalogReply: Decodable { let page: InspectorProjectPage }
private struct ResolutionReply: Decodable {
    struct Resolution: Decodable { let project_id: String }
    let resolution: Resolution
}
private struct BindingsReply: Decodable { let bindings: [InspectorBinding] }
private struct PolicyReply: Decodable { let policy: InspectorPolicy }
private struct CoverageReply: Decodable { let coverage: InspectorPolicyCoverage }
private struct BackboneReply: Decodable { let backbone: InspectorBackbone }
private struct KnowledgeReply: Decodable { let page: InspectorKnowledgePage }
private struct InvocationReply: Decodable { let page: InspectorInvocationPage }

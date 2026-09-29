import Foundation

/// The bounded wire projection of one logical Project from one publisher.
struct ProjectMeshSnapshot: Codable, Equatable, Identifiable {
    let type: String
    let sessionId: String
    let projectId: String
    var publisherEndpointId: String? = nil
    let project: ProjectMeshProject
    var bindings: [ProjectBindingSummary]? = nil
    var peers: [ProjectIntegrationPeer]? = nil
    var skills: [ProjectSharedSkill]? = nil
    var mcpServers: [ProjectMcpServer]? = nil
    var capabilityRequests: [ProjectCapabilityRequest]? = nil
    var capabilityObservations: [ProjectCapabilityObservation]? = nil
    var incomplete: Bool? = nil
    var execution: ProjectExecutionPolicy? = nil
    var restrictions: ProjectRestrictionSet? = nil
    var environment: ProjectEnvironment? = nil
    var modelCatalog: [ProjectEndpointModelCatalog]? = nil
    var backbone: ProjectBackbone? = nil
    var repositoryGraphs: [ProjectRepositoryGraph]? = nil
    var repositoryDetails: [ProjectRepositoryDetails]? = nil
    var cortex: [ProjectCortexIntegration]? = nil
    var knowledge: [ProjectKnowledgeRecord]? = nil
    var supersededKnowledgeRecordIds: [String]? = nil
    var tasks: [ProjectMeshTask]
    var executions: [ExecutionSessionLink]
    var claims: [ProjectResourceClaim]
    var dependencies: [ProjectTaskDependency]
    var events: [ProjectMeshEvent]
    let generatedAt: Double
    var id: String { projectId }
}

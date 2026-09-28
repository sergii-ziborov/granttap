import Foundation

struct ProjectExecutionPolicy: Codable, Equatable {
    let mode: String
    var targetEndpointId: String? = nil
    var defaultProvider: String? = nil
    var defaultModel: String? = nil
    let revision: Int
    var hostGrantId: String? = nil
    var hostGrantStatus: String = "none"
    var offlineBehavior: String = "reject"
}

struct ProjectHostGrant: Codable {
    let type: String
    let projectId: String
    let grant: String
    let revision: Int
    var instanceEpoch: String? = nil
    let createdAt: Double

    init(projectId: String, grant: String, revision: Int, instanceEpoch: String? = nil, createdAt: Double) {
        type = "project.execution.host-grant"
        self.projectId = projectId
        self.grant = grant
        self.revision = revision
        self.instanceEpoch = instanceEpoch
        self.createdAt = createdAt
    }
}

struct ProjectRestrictionRule: Codable, Equatable, Identifiable {
    let ruleId: String
    let kind: String
    var limit: Int? = nil
    var name: String? = nil
    var paths: [String]? = nil
    var effect: String = "deny"
    var id: String { ruleId }
}

struct ProjectRestrictionSet: Codable, Equatable {
    let projectId: String
    let revision: Int
    let scope: String
    var repositoryId: String? = nil
    let rules: [ProjectRestrictionRule]
    var source: String = "phone"
}

struct ProjectEnvironmentVariable: Codable, Equatable, Identifiable {
    let key: String
    var value: String? = nil
    let secret: Bool
    var id: String { key }
}

struct ProjectEnvironment: Codable, Equatable {
    let projectId: String
    let revision: Int
    var shareNonSecretsWithRepo: Bool = false
    let variables: [ProjectEnvironmentVariable]
}

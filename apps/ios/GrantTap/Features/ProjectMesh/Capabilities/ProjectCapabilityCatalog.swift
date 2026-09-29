import Foundation

struct ProjectSharedSkill: Codable, Equatable, Identifiable {
    let name: String
    var endpointId: String? = nil
    var description: String? = nil
    var version: String? = nil
    var digest: String? = nil
    var source: String? = nil
    var state: String? = nil
    var id: String { "\(endpointId ?? "")\u{1f}\(name)" }
}

struct ProjectAdvertisedModel: Codable, Equatable, Identifiable {
    let modelId: String
    let provider: String
    let endpointId: String
    let source: String
    var label: String? = nil
    var description: String? = nil
    var priority: Int? = nil
    let observedAt: Double
    var id: String { "\(endpointId):\(provider):\(modelId)" }
}

struct ProjectEndpointModelCatalog: Codable, Equatable, Identifiable {
    let endpointId: String
    let observedAt: Double
    var stale: Bool? = nil
    let models: [ProjectAdvertisedModel]
    var reason: String? = nil
    var id: String { endpointId }
}

struct ProjectMcpServer: Codable, Equatable, Identifiable {
    let name: String
    var title: String? = nil
    let provider: String
    let endpointId: String
    let configuredEnabled: Bool
    let allowed: Bool
    var authStatus: String? = nil
    var version: String? = nil
    var configDigest: String? = nil
    var metadataSource: String? = nil
    let sessionIds: [String]
    var id: String {
        "\(endpointId)\u{1f}\(provider)\u{1f}\(name)\u{1f}\(version ?? "")\u{1f}\(configDigest ?? "")\u{1f}\(authStatus ?? "")"
    }
}

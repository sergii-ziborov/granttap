import Foundation

struct ProjectCortexPacketStatus: Codable, Equatable {
    var packetId: String? = nil
    var snapshotId: String? = nil
    let included: Int
    let omitted: Int
    let rawEstimatedTokens: Int
    let selectedEstimatedTokens: Int
    let omittedEstimatedTokens: Int
    let deduplicatedLines: Int
    let requiresUpstream: Bool
}

struct ProjectCortexIntegration: Codable, Equatable, Identifiable {
    let projectId: String
    let endpointId: String
    let enabled: Bool
    let maxTokens: Int
    let state: String
    var version: String? = nil
    var revision: String? = nil
    var weavatrixVersion: String? = nil
    var packet: ProjectCortexPacketStatus? = nil
    var detail: String? = nil
    let checkedAt: Double
    var id: String { endpointId }
}

struct CortexIntegrationSet: Codable {
    let projectId: String
    let enabled: Bool
    let maxTokens: Int
}

import Foundation

struct ProjectNetworkEndpoint: Codable, Equatable {
    let id: String
    let room: String
    let relayUrl: String
    let publicKey: String
    var controllerPublicKey: String? = nil
}

struct ProjectNetworkPeer: Codable, Equatable {
    struct Outgoing: Codable, Equatable {
        let relayUrl: String
        let room: String
        let writerId: String
        let secret: String
        let scopeHash: String
        let expiresAt: Double
    }
    let endpointId: String
    let publicKey: String
    let incomingWriterId: String
    let outgoing: Outgoing
}

struct ProjectTransportCommand: Codable, Equatable {
    var type = "project.transport.set"
    let sessionId: String
    let projectId: String
    let targetEndpointId: String
    let requestId: String
    let revision: Int
    let enabled: Bool
    let expiresAt: Double
    let routingEnabled: Bool
    let createdAt: Double
    let allowCrossPlatform: Bool
    let cooldownMs: Int
    let peers: [ProjectNetworkPeer]
}

struct ProjectTransportAck: Codable, Equatable {
    var type = "project.transport.ack"
    let sessionId: String
    let projectId: String
    let targetEndpointId: String
    let requestId: String
    let revision: Int
    let accepted: Bool
    let generatedAt: Double
}

struct ProjectWriterGrant: Codable, Equatable {
    let sourceKeyId: String
    let recipientKeyId: String
    let scopeHash: String
    let tokenHash: String
    let expiresAt: Double
}

struct ProjectNetworkWriter: Codable, Equatable {
    let ownerEndpointId: String
    let id: String
    let grant: ProjectWriterGrant
}

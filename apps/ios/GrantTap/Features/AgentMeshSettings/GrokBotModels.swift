import Foundation

struct GrokBotMeshEndpoint: Codable, Equatable, Identifiable {
    let endpointId: String
    let kind: String
    let displayName: String
    let publicKey: String
    let credentialId: String
    var status: String
    let createdAt: Double
    var id: String { endpointId }
}

struct GrokBotMeshActor: Codable, Equatable, Identifiable {
    let actorId: String
    let endpointId: String
    let kind: String
    let displayName: String
    var status: String
    var enabled: Bool
    var id: String { actorId }
}

struct GrokBotScopedCredential: Codable, Equatable {
    let credentialId: String
    let endpointId: String
    var status: String
    var projectIds: [String]
    var taskIds: [String]?
    let operations: [String]
    let issuedAt: Double
    let expiresAt: Double
    var revokedAt: Double?
}

struct GrokBotActorPolicy: Codable, Equatable {
    let actorId: String
    let enabled: Bool
}

struct GrokBotEndpointPolicy: Codable, Equatable {
    let type: String
    let endpointId: String
    let credentialId: String
    let enabled: Bool
    let status: String
    let projectIds: [String]
    let actors: [GrokBotActorPolicy]
    let revision: Int
    let createdAt: Double
}

struct GrokBotEndpointConnection: Codable, Equatable {
    let version: Int
    var endpoint: GrokBotMeshEndpoint
    var credential: GrokBotScopedCredential
    var actors: [GrokBotMeshActor]
    let phonePairing: Pairing
    var policy: GrokBotEndpointPolicy
    let inviteExpiresAt: Double
}

struct GrokBotInviteBundle: Codable {
    let version: Int
    let endpoint: GrokBotMeshEndpoint
    let credential: GrokBotScopedCredential
    let actors: [GrokBotMeshActor]
    let pairing: Pairing
    let policy: GrokBotEndpointPolicy
    let inviteExpiresAt: Double
}

enum GrokBotEndpointStore {
    static let service = "com.ziborov.granttap.grok-bot-mesh"

    static func load() -> GrokBotEndpointConnection? {
        guard let data = KeychainPairing.load(service: service) else { return nil }
        return try? JSONDecoder().decode(GrokBotEndpointConnection.self, from: data)
    }

    @discardableResult
    static func save(_ value: GrokBotEndpointConnection) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return KeychainPairing.save(data, service: service)
    }

    static func remove() {
        KeychainPairing.remove(service: service)
    }
}

enum GrokBotAuthorization {
    static func accepts(
        _ event: ProjectMeshEvent,
        endpointId: String,
        connection: GrokBotEndpointConnection?,
        meshEnabled: Bool,
        now: Double = Date().timeIntervalSince1970 * 1_000
    ) -> Bool {
        guard meshEnabled,
              let connection,
              connection.endpoint.endpointId == endpointId,
              connection.credential.status == "active",
              connection.credential.expiresAt > now,
              connection.credential.projectIds.contains(event.projectId),
              connection.credential.taskIds?.contains(event.taskId) ?? true,
              let actorId = event.sourceActorId,
              connection.actors.contains(where: { $0.actorId == actorId && $0.enabled }),
              let operation = operation(for: event.eventType),
              connection.credential.operations.contains(operation)
        else { return false }
        return true
    }

    static func operation(for eventType: String) -> String? {
        switch eventType {
        case "TASK_PROGRESS", "TASK_BLOCKED", "DEPENDENCY": return "progress"
        case "RESOURCE_CLAIM": return "claim"
        case "RESOURCE_RELEASE": return "release"
        case "AGENT_QUESTION": return "question"
        case "AGENT_ANSWER": return "answer"
        case "HANDOFF_REQUEST": return "handoff"
        case "HANDOFF_ACCEPTED": return "accept_handoff"
        case "HANDOFF_REJECTED": return "reject_handoff"
        case "ARTIFACT_READY", "COMMIT_READY": return "artifact_ready"
        case "TASK_COMPLETED": return "complete"
        default: return nil
        }
    }
}

import CryptoKit
import Foundation

enum ProjectNetworkError: Error {
    case invalidScope, secureStorage, relayUnavailable, notConfirmed
}

struct ProjectNetworkPlan: Codable, Equatable {
    let projectId: String
    let endpoints: [ProjectNetworkEndpoint]
    let revision: Int
    let commands: [ProjectTransportCommand]
    let writers: [ProjectNetworkWriter]
    var confirmedEndpoints: Set<String> = []

    /// Permission changes retain manual transport grants and their FIFO identity.
    func changingRouting(_ enabled: Bool, allowCrossPlatform: Bool? = nil, now: Double) -> ProjectNetworkPlan {
        let stamp = max(now, (commands.map(\.createdAt).max() ?? 0) + 1)
        let changed = commands.map { command in
            ProjectTransportCommand(sessionId: command.sessionId, projectId: command.projectId,
                targetEndpointId: command.targetEndpointId, requestId: UUID().uuidString.lowercased(),
                revision: command.revision, enabled: command.enabled, expiresAt: command.expiresAt,
                routingEnabled: enabled, createdAt: stamp, allowCrossPlatform: allowCrossPlatform ?? command.allowCrossPlatform,
                cooldownMs: command.cooldownMs, peers: command.peers)
        }
        return ProjectNetworkPlan(projectId: projectId, endpoints: endpoints, revision: revision,
            commands: changed, writers: writers)
    }

    static func make(projectId: String, endpoints: [ProjectNetworkEndpoint], routingEnabled: Bool, allowCrossPlatform: Bool = false,
                     revision: Int, now: Double) throws -> ProjectNetworkPlan {
        guard !projectId.isEmpty, projectId.utf8.count <= 128, revision >= 0,
              now.isFinite, now >= 0, now == floor(now), (1...16).contains(endpoints.count),
              Set(endpoints.map(\.id)).count == endpoints.count,
              Set(endpoints.map(\.room)).count == endpoints.count,
              Set(endpoints.map(\.publicKey)).count == endpoints.count,
              endpoints.allSatisfy(validEndpoint) else { throw ProjectNetworkError.invalidScope }
        let ordered = endpoints.sorted { $0.id < $1.id }
        let expiry = now + 29 * 86_400_000
        var grants: [String: ProjectNetworkPeer.Outgoing] = [:]
        var writers: [ProjectNetworkWriter] = []
        for source in ordered {
            for target in ordered where target.id != source.id {
                let secret = try Crypto.randomBytes(32).map { String(format: "%02x", $0) }.joined()
                let writerId = "writer-\(UUID().uuidString.lowercased())"
                let scopeHash = try scope(projectId: projectId, source: source.id, target: target.id, revision: revision)
                grants[pair(source.id, target.id)] = .init(relayUrl: target.relayUrl, room: target.room,
                    writerId: writerId, secret: secret, scopeHash: scopeHash, expiresAt: expiry)
                guard let sourceKey = CiphertextRecipient.identifier(publicKey: source.publicKey),
                      let targetKey = CiphertextRecipient.identifier(publicKey: target.publicKey) else {
                    throw ProjectNetworkError.invalidScope
                }
                writers.append(.init(ownerEndpointId: target.id, id: writerId, grant: .init(
                    sourceKeyId: sourceKey, recipientKeyId: targetKey, scopeHash: scopeHash,
                    tokenHash: digest(Data(secret.utf8)), expiresAt: expiry)))
            }
        }
        let commands = try ordered.map { source in
            let peers = try ordered.filter { $0.id != source.id }.map { target in
                guard let outgoing = grants[pair(source.id, target.id)],
                      let incoming = grants[pair(target.id, source.id)] else { throw ProjectNetworkError.invalidScope }
                return ProjectNetworkPeer(endpointId: target.id, publicKey: target.publicKey,
                    incomingWriterId: incoming.writerId, outgoing: outgoing)
            }
            return ProjectTransportCommand(sessionId: projectId, projectId: projectId, targetEndpointId: source.id,
                requestId: UUID().uuidString.lowercased(), revision: revision, enabled: true, expiresAt: expiry,
                routingEnabled: routingEnabled, createdAt: now, allowCrossPlatform: allowCrossPlatform,
                cooldownMs: 300_000, peers: peers)
        }
        return ProjectNetworkPlan(projectId: projectId, endpoints: ordered, revision: revision,
            commands: commands, writers: writers)
    }

    static func scope(projectId: String, source: String, target: String, revision: Int) throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject:
            ["granttap-task-network-v1", projectId, source, target, revision], options: [.withoutEscapingSlashes])
        return digest(bytes)
    }

    private static func pair(_ source: String, _ target: String) -> String { "\(source)\u{0}\(target)" }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private static func validEndpoint(_ endpoint: ProjectNetworkEndpoint) -> Bool {
        guard !endpoint.id.isEmpty, endpoint.id.utf8.count <= 128,
              endpoint.room.range(of: "^[a-f0-9]{16,64}$", options: .regularExpression) != nil,
              Data(base64Encoded: endpoint.publicKey)?.count == 32,
              let url = URLComponents(string: endpoint.relayUrl), url.host?.isEmpty == false,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
        return ["wss", "https"].contains(url.scheme ?? "")
            || (["ws", "http"].contains(url.scheme ?? "") && ["localhost", "127.0.0.1", "::1"].contains(url.host ?? ""))
    }
}

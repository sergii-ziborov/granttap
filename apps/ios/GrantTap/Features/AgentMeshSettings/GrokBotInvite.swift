import Foundation
import TweetNacl

enum GrokBotInviteError: LocalizedError {
    case noComputer, noProject, alreadyConnected, keyGeneration, relayUnavailable, storage

    var errorDescription: String? {
        switch self {
        case .noComputer: return L("Connect a computer before adding Grok Bot.")
        case .noProject: return L("Select at least one available Project.")
        case .alreadyConnected: return L("Revoke the current Grok Bot connection first.")
        case .keyGeneration: return L("GrantTap could not create endpoint keys.")
        case .relayUnavailable: return L("The relay could not create the one-time Mesh Invite.")
        case .storage: return L("The Grok Bot endpoint could not be stored securely.")
        }
    }
}

extension AppModel {
    typealias GrokBotInviteParker = (URLRequest, Data) async throws -> Int

    func createGrokBotInvite(
        projectIds requested: Set<String>,
        parker: GrokBotInviteParker? = nil
    ) async throws -> String {
        if let current = grokBotConnection, current.credential.status != "revoked" {
            throw GrokBotInviteError.alreadyConnected
        }
        guard let sourcePairing = connectionRegistry.preferred?.pairing else {
            throw GrokBotInviteError.noComputer
        }
        let projectIds = requested.filter { meshSnapshots[$0] != nil }.sorted()
        guard !projectIds.isEmpty else { throw GrokBotInviteError.noProject }
        let generated = try makeGrokBotConnection(
            projectIds: projectIds, relayUrl: sourcePairing.relayUrl
        )
        let connection = generated.connection
        let bundle = GrokBotInviteBundle(
            version: connection.version, endpoint: connection.endpoint,
            credential: connection.credential, actors: connection.actors,
            pairing: generated.botPairing, policy: connection.policy,
            inviteExpiresAt: connection.inviteExpiresAt
        )
        let data = try JSONEncoder().encode(bundle)
        let transferKey = base64URL(Crypto.randomBytes(32))
        guard let sealed = Crypto.openableSeal(data, key: transferKey),
              let base = Pairing.normalizedPairingHTTPBase(sourcePairing.relayUrl)
        else { throw GrokBotInviteError.keyGeneration }
        let mailbox = hex(Crypto.randomBytes(16))
        let body = try JSONEncoder().encode(sealed)
        var request = URLRequest(url: URL(string: "\(base)/pair/\(mailbox)")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let status: Int
        if let parker {
            status = try await parker(request, body)
        } else {
            let (_, response) = try await URLSession.shared.upload(for: request, from: body)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        }
        guard status == 201 else { throw GrokBotInviteError.relayUnavailable }
        guard GrokBotEndpointStore.save(connection) else { throw GrokBotInviteError.storage }
        grokBotConnection = connection
        attachGrokBotEndpoint(connection)
        return meshInviteURI(base: base, mailbox: mailbox, key: transferKey)
    }

    private func makeGrokBotConnection(
        projectIds: [String], relayUrl: String
    ) throws -> (connection: GrokBotEndpointConnection, botPairing: Pairing) {
        let phone = try NaclBox.keyPair()
        let bot = try NaclBox.keyPair()
        let now = Date().timeIntervalSince1970 * 1_000
        let endpointId = "grok-\(hex(Crypto.randomBytes(8)))"
        let credentialId = "cred-\(hex(Crypto.randomBytes(12)))"
        let endpoint = GrokBotMeshEndpoint(
            endpointId: endpointId, kind: "grok_bot_cloud", displayName: "Grok Bot Cloud",
            publicKey: base64URL(bot.publicKey), credentialId: credentialId,
            status: "pending", createdAt: now
        )
        let actors = defaultGrokBotActors(endpointId: endpointId)
        let credential = GrokBotScopedCredential(
            credentialId: credentialId, endpointId: endpointId, status: "active",
            projectIds: projectIds, operations: Self.grokBotOperations,
            issuedAt: now, expiresAt: now + 30 * 24 * 60 * 60 * 1_000
        )
        let policy = GrokBotEndpointPolicy(
            type: "mesh.endpoint.policy", endpointId: endpointId, credentialId: credentialId,
            enabled: agentMeshPreferences.meshEnabled, status: "active", projectIds: projectIds,
            actors: actors.map { .init(actorId: $0.actorId, enabled: $0.enabled) },
            revision: 1, createdAt: now
        )
        let phonePairing = Pairing(
            relayUrl: relayUrl, room: hex(Crypto.randomBytes(16)), role: "phone",
            deviceName: "iPhone", senderId: hex(Crypto.randomBytes(4)),
            myPublicKey: phone.publicKey.base64EncodedString(),
            mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: bot.publicKey.base64EncodedString(),
            pushAuth: hex(Crypto.randomBytes(32))
        )
        let connection = GrokBotEndpointConnection(
            version: 1, endpoint: endpoint, credential: credential, actors: actors,
            phonePairing: phonePairing, policy: policy, inviteExpiresAt: now + 15 * 60 * 1_000
        )
        let botPairing = Pairing(
            relayUrl: relayUrl, room: phonePairing.room, role: "machine",
            deviceName: endpoint.displayName, senderId: "bot-\(phonePairing.senderId)",
            myPublicKey: bot.publicKey.base64EncodedString(),
            mySecretKey: bot.secretKey.base64EncodedString(),
            peerPublicKey: phone.publicKey.base64EncodedString(), pushAuth: phonePairing.pushAuth
        )
        return (connection, botPairing)
    }

    private func defaultGrokBotActors(endpointId: String) -> [GrokBotMeshActor] {
        [
            .init(actorId: "qa-bot", endpointId: endpointId, kind: "persistent_agent",
                  displayName: "QA Bot", status: "idle", enabled: true),
            .init(actorId: "research-bot", endpointId: endpointId, kind: "persistent_agent",
                  displayName: "Research Bot", status: "idle", enabled: true),
            .init(actorId: "release-bot", endpointId: endpointId, kind: "persistent_agent",
                  displayName: "Release Bot", status: "idle", enabled: false),
        ]
    }

    private func meshInviteURI(base: String, mailbox: String, key: String) -> String {
        var components = URLComponents()
        components.scheme = "granttap"
        components.host = "mesh-invite"
        components.queryItems = [
            .init(name: "v", value: "1"), .init(name: "u", value: base),
            .init(name: "m", value: mailbox), .init(name: "k", value: key),
        ]
        return components.string ?? ""
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static let grokBotOperations = [
        "status", "task", "claim", "release", "progress", "question", "answer",
        "handoff", "accept_handoff", "reject_handoff", "artifact_ready", "complete",
    ]
}

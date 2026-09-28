import XCTest
@testable import GrantTap

@MainActor
final class GrokBotSecurityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        GrokBotEndpointStore.remove()
    }

    override func tearDown() {
        GrokBotEndpointStore.remove()
        super.tearDown()
    }

    func testInviteIsEncryptedScopedAndContainsNoAdministrativeOperation() async throws {
        let model = AppModel()
        model.grokBotConnection = nil
        model.connectionRegistry = registry()
        model.meshSnapshots = ["project": snapshot()]
        var parkedBody = Data()
        let invite = try await model.createGrokBotInvite(projectIds: ["project"]) {
            request, body in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertTrue(request.url?.path.hasPrefix("/pair/") == true)
            parkedBody = body
            return 201
        }
        model.meshEndpointRelaysById.values.forEach { $0.disconnect() }

        let bodyText = String(decoding: parkedBody, as: UTF8.self)
        XCTAssertFalse(bodyText.contains("project"))
        XCTAssertFalse(bodyText.contains("credentialId"))
        let parts = URLComponents(string: invite)?.queryItems ?? []
        let key = try XCTUnwrap(parts.first(where: { $0.name == "k" })?.value)
        let sealed = try JSONDecoder().decode(Crypto.SealResult.self, from: parkedBody)
        let plain = try XCTUnwrap(Crypto.openWithTransferKey(
            nonceB64: sealed.nonce, boxB64: sealed.box, key: key
        ))
        let bundle = try JSONDecoder().decode(GrokBotInviteBundle.self, from: plain)
        XCTAssertEqual(bundle.credential.projectIds, ["project"])
        XCTAssertEqual(Set(bundle.actors.map(\.displayName)), ["QA Bot", "Research Bot", "Release Bot"])
        XCTAssertFalse(bundle.credential.operations.contains("setup"))
        XCTAssertFalse(bundle.credential.operations.contains("mesh_create_invite"))
        XCTAssertEqual(bundle.endpoint.kind, "grok_bot_cloud")
    }

    func testAuthorizationRejectsDisabledActorScopeOperationAndRevocation() {
        var connection = connection()
        let allowed = event(type: "TASK_PROGRESS", actorId: "qa-bot")
        XCTAssertTrue(GrokBotAuthorization.accepts(
            allowed, endpointId: "endpoint", connection: connection,
            meshEnabled: true, now: 2
        ))
        XCTAssertFalse(GrokBotAuthorization.accepts(
            allowed, endpointId: "endpoint", connection: connection,
            meshEnabled: false, now: 2
        ))
        XCTAssertFalse(GrokBotAuthorization.accepts(
            event(type: "UNKNOWN", actorId: "qa-bot"), endpointId: "endpoint",
            connection: connection, meshEnabled: true, now: 2
        ))
        connection.actors[0].enabled = false
        XCTAssertFalse(GrokBotAuthorization.accepts(
            allowed, endpointId: "endpoint", connection: connection,
            meshEnabled: true, now: 2
        ))
        connection.credential.status = "revoked"
        XCTAssertFalse(GrokBotAuthorization.accepts(
            allowed, endpointId: "endpoint", connection: connection,
            meshEnabled: true, now: 2
        ))
    }

    private func registry() -> ConnectionRegistry {
        let pairing = Pairing(
            relayUrl: "wss://relay.granttap.ai", room: "room", role: "phone",
            deviceName: "Mac", senderId: "phone", myPublicKey: "a",
            mySecretKey: "b", peerPublicKey: "c", pushAuth: "d"
        )
        let linked = LinkedComputer(
            id: "room", pairing: pairing, label: "Mac", addedAt: 1,
            lastCatalogAt: 1, lastMachineName: "Mac"
        )
        return .init(connections: [linked], preferredId: "room")
    }

    private func snapshot() -> ProjectMeshSnapshot {
        .init(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
    }

    private func connection() -> GrokBotEndpointConnection {
        let pairing = registry().connections[0].pairing
        let actor = GrokBotMeshActor(
            actorId: "qa-bot", endpointId: "endpoint", kind: "persistent_agent",
            displayName: "QA Bot", status: "idle", enabled: true
        )
        let credential = GrokBotScopedCredential(
            credentialId: "credential", endpointId: "endpoint", status: "active",
            projectIds: ["project"], taskIds: ["task"], operations: ["progress"],
            issuedAt: 1, expiresAt: 100
        )
        return .init(
            version: 1,
            endpoint: .init(endpointId: "endpoint", kind: "grok_bot_cloud",
                            displayName: "Grok Bot Cloud", publicKey: "key",
                            credentialId: "credential", status: "active", createdAt: 1),
            credential: credential, actors: [actor], phonePairing: pairing,
            policy: .init(type: "mesh.endpoint.policy", endpointId: "endpoint",
                          credentialId: "credential", enabled: true, status: "active",
                          projectIds: ["project"], actors: [.init(actorId: "qa-bot", enabled: true)],
                          revision: 1, createdAt: 1),
            inviteExpiresAt: 100
        )
    }

    private func event(type: String, actorId: String) -> ProjectMeshEvent {
        .init(type: "mesh.event", sessionId: "task", eventId: UUID().uuidString,
              projectId: "project", taskId: "task", sourceSessionId: "actor:\(actorId)",
              sourceActorId: actorId, eventType: type, createdAt: 2,
              payload: .init(summary: "Progress"))
    }
}

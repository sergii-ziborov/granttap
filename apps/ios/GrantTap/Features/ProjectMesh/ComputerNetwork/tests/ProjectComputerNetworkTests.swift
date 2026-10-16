import XCTest
import CryptoKit
@testable import GrantTap

final class ProjectComputerNetworkTests: XCTestCase {
    func testAutomaticPermissionChangesRetainManualTransportAndClearOldConfirmations() throws {
        let endpoint = ProjectNetworkEndpoint(id: "target", room: String(repeating: "a", count: 32),
            relayUrl: "wss://relay.test", publicKey: Data(repeating: 1, count: 32).base64EncodedString())
        var plan = try ProjectNetworkPlan.make(projectId: "project", endpoints: [endpoint], routingEnabled: false,
            revision: 12, now: 100)
        plan.confirmedEndpoints.insert("target")
        let changed = plan.changingRouting(true, now: 100)
        XCTAssertEqual(changed.revision, plan.revision)
        XCTAssertEqual(changed.writers, plan.writers)
        XCTAssertEqual(changed.commands.first?.peers, plan.commands.first?.peers)
        XCTAssertEqual(changed.commands.first?.createdAt, 101)
        XCTAssertNotEqual(changed.commands.first?.requestId, plan.commands.first?.requestId)
        XCTAssertEqual(changed.commands.first?.routingEnabled, true)
        XCTAssertTrue(changed.confirmedEndpoints.isEmpty)
    }
    func testPersistedConfigurationContainsOnlyCiphertextAndOpensOnlyOnTheTargetComputer() throws {
        let phone = Curve25519.KeyAgreement.PrivateKey(), machine = Curve25519.KeyAgreement.PrivateKey()
        let endpoint = ProjectNetworkEndpoint(id: "target", room: String(repeating: "a", count: 32),
            relayUrl: "wss://relay.test", publicKey: machine.publicKey.rawRepresentation.base64EncodedString())
        let pairing = Pairing(relayUrl: endpoint.relayUrl, room: endpoint.room, role: "phone", deviceName: "Fixture",
            senderId: "fixture", myPublicKey: phone.publicKey.rawRepresentation.base64EncodedString(),
            mySecretKey: phone.rawRepresentation.base64EncodedString(), peerPublicKey: endpoint.publicKey)
        let plan = try ProjectNetworkPlan.make(projectId: "repo/project", endpoints: [endpoint],
            routingEnabled: false, revision: 12, now: 100)
        let command = try XCTUnwrap(plan.commands.first)
        let body = try ProjectNetworkConfigurationHTTP.prepare(command, pairing: pairing)
        let envelope = body.envelope
        let plain = try XCTUnwrap(Crypto.open(nonceB64: envelope.nonce, boxB64: envelope.box,
            theirPublicKeyB64: pairing.myPublicKey, mySecretKeyB64: machine.rawRepresentation.base64EncodedString()))
        XCTAssertEqual(try JSONDecoder().decode(ProjectTransportCommand.self, from: plain), command)
        XCTAssertEqual(envelope.expiresAt, command.expiresAt)
        XCTAssertEqual(envelope.deliveryId, try ProjectNetworkConfigurationHTTP.identifier(projectId: "repo/project", endpointId: "target"))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(body), as: UTF8.self).contains("repo/project"))
    }
    @MainActor
    func testProvisioningPersistsGrantsBeforePublishingAndWaitsForBothComputerConfirmations() async throws {
        let endpoints = ["source", "target"].enumerated().map { index, id in
            ProjectNetworkEndpoint(id: id, room: String(repeating: index == 0 ? "a" : "b", count: 32),
                relayUrl: "wss://relay.test", publicKey: Data(repeating: UInt8(index + 1), count: 32).base64EncodedString())
        }
        var saved: ProjectNetworkPlan?
        var uploads = 0, configurations = 0
        var coordinator: ProjectNetworkCoordinator!
        coordinator = ProjectNetworkCoordinator(load: { _ in saved }, save: { saved = $0 },
            publish: { _, _ in
                XCTAssertNotNil(saved, "Private writer credentials must be recoverable before any HTTP grant is created.")
                uploads += 1
            }, publishConfiguration: { command, pairing in
                XCTAssertEqual(saved?.projectId, command.projectId)
                XCTAssertTrue(endpoints.contains { $0.id == command.targetEndpointId && $0.room == pairing.room })
                configurations += 1
            }, clock: { 100 })
        let pairings = Dictionary(uniqueKeysWithValues: endpoints.map { endpoint in
            (endpoint.id, Pairing(relayUrl: endpoint.relayUrl, room: endpoint.room, role: "phone",
                deviceName: "Fixture", senderId: "fixture", myPublicKey: "", mySecretKey: "",
                peerPublicKey: endpoint.publicKey, pushAuth: "synthetic-owner-credential"))
        })
        let send: ProjectNetworkCoordinator.Send = { command, endpoint in
            XCTAssertEqual(configurations, 2, "Relay configuration must survive closing the phone before either WebSocket send.")
            coordinator.receive(.init(sessionId: "project", projectId: "project", targetEndpointId: endpoint.id,
                requestId: command.requestId, revision: command.revision, accepted: true, generatedAt: 100), room: endpoint.room)
        }
        try await coordinator.ensure(projectId: "project", endpoints: endpoints, pairings: pairings, send: send)
        XCTAssertEqual(uploads, 2)
        XCTAssertEqual(configurations, 2)
        XCTAssertEqual(saved?.confirmedEndpoints.count, 2)
        try await coordinator.ensure(projectId: "project", endpoints: endpoints.reversed(), pairings: pairings, send: send)
        XCTAssertEqual(uploads, 2, "A confirmed, unchanged Project can transfer while the phone later goes away.")
    }

    func testPairwiseGrantsKeepRoomOwnerCredentialsOutOfComputerConfigurations() throws {
        let source = ProjectNetworkEndpoint(id: "source", room: String(repeating: "a", count: 32),
            relayUrl: "wss://relay.test", publicKey: Data(repeating: 1, count: 32).base64EncodedString())
        let target = ProjectNetworkEndpoint(id: "target", room: String(repeating: "b", count: 32),
            relayUrl: "wss://relay.test", publicKey: Data(repeating: 2, count: 32).base64EncodedString())
        let plan = try ProjectNetworkPlan.make(projectId: "repo/project", endpoints: [source, target],
            routingEnabled: false, revision: 12, now: 100)
        XCTAssertEqual(plan.writers.count, 2)
        XCTAssertEqual(plan.commands.count, 2)
        let outgoing = try XCTUnwrap(plan.commands.first { $0.targetEndpointId == "source" }?.peers.first)
        let incoming = try XCTUnwrap(plan.commands.first { $0.targetEndpointId == "target" }?.peers.first)
        XCTAssertEqual(outgoing.outgoing.writerId, incoming.incomingWriterId)
        XCTAssertEqual(outgoing.outgoing.room, target.room)
        XCTAssertEqual(outgoing.outgoing.scopeHash,
            try ProjectNetworkPlan.scope(projectId: "repo/project", source: "source", target: "target", revision: 12))
        XCTAssertEqual(outgoing.outgoing.scopeHash,
            "bdefe35c2c7def1872029c4a8a9649feb3a5299a7a60dac86f2f18ec98a97d3a",
            "The Project scope must match the TypeScript wire contract, including slash escaping.")
        XCTAssertEqual(outgoing.outgoing.secret.count, 64)
        XCTAssertNotEqual(outgoing.outgoing.secret, incoming.outgoing.secret)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(outgoing)) as? [String: Any]
        XCTAssertNil(json?["pushAuth"])
        XCTAssertFalse(plan.commands.contains { $0.routingEnabled })
        XCTAssertThrowsError(try ProjectNetworkPlan.make(projectId: "project", endpoints: [source, source],
            routingEnabled: true, revision: 13, now: 100))
    }

    func testTransportAcknowledgementRequiresEveryExactComputerAndRevision() throws {
        let endpoint = ProjectNetworkEndpoint(id: "source", room: String(repeating: "a", count: 32),
            relayUrl: "wss://relay.test", publicKey: Data(repeating: 1, count: 32).base64EncodedString())
        let plan = try ProjectNetworkPlan.make(projectId: "project", endpoints: [endpoint],
            routingEnabled: false, revision: 12, now: 100)
        var progress = ProjectNetworkConfirmation(plan: plan)
        let command = try XCTUnwrap(plan.commands.first)
        let ack = ProjectTransportAck(sessionId: "project", projectId: "project", targetEndpointId: "source",
            requestId: command.requestId, revision: 12, accepted: true, generatedAt: 200)
        XCTAssertFalse(progress.receive(ack, room: "foreign"))
        XCTAssertFalse(progress.isConfirmed)
        XCTAssertTrue(progress.receive(ack, room: endpoint.room))
        XCTAssertTrue(progress.isConfirmed)
    }
}

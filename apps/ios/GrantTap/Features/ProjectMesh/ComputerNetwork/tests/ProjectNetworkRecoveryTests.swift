import XCTest
@testable import GrantTap

@MainActor
final class ProjectNetworkRecoveryTests: XCTestCase {
    func testInterruptedProvisioningReusesDurableGrantsAndConfirmsTheNativeComputer() async throws {
        let endpoints = ["local", "remote"].enumerated().map { index, id in
            ProjectNetworkEndpoint(id: id, room: String(repeating: index == 0 ? "a" : "b", count: 32),
                relayUrl: "wss://relay.test", publicKey: Data(repeating: UInt8(index + 1), count: 32).base64EncodedString())
        }
        let remote = endpoints[1]
        let pairing = Pairing(relayUrl: remote.relayUrl, room: remote.room, role: "phone", deviceName: "Fixture",
            senderId: "fixture", myPublicKey: "", mySecretKey: "", peerPublicKey: remote.publicKey)
        var saved: ProjectNetworkPlan?
        let failed = ProjectNetworkCoordinator(load: { _ in nil }, save: { saved = $0 },
            publish: { _, _ in throw ProjectNetworkError.relayUnavailable },
            nativeGrant: { _, _ in }, clock: { 100 })
        do {
            try await failed.ensure(projectId: "project", endpoints: endpoints, pairings: [remote.id: pairing],
                nativeEndpointId: "local", send: { _, _ in XCTFail("An incomplete publication cannot be sent.") })
            XCTFail("A failed relay publication cannot confirm the network.")
        } catch { XCTAssertEqual(failed.states["project"], .failed) }
        let interrupted = try XCTUnwrap(saved)
        XCTAssertTrue(interrupted.confirmedEndpoints.isEmpty)
        var nativeGrants = 0
        var recovered: ProjectNetworkCoordinator!
        recovered = ProjectNetworkCoordinator(load: { _ in saved }, save: { saved = $0 },
            publish: { writer, _ in XCTAssertTrue(interrupted.writers.contains(writer)) },
            publishConfiguration: { _, _ in }, nativeGrant: { writer, project in
                XCTAssertEqual(project, "project")
                XCTAssertEqual(writer.ownerEndpointId, "local")
                XCTAssertTrue(interrupted.writers.contains(writer))
                nativeGrants += 1
            }, nativeConfiguration: { command in
                .init(sessionId: command.sessionId, projectId: command.projectId,
                    targetEndpointId: command.targetEndpointId, requestId: command.requestId,
                    revision: command.revision, accepted: true, generatedAt: 100)
            }, clock: { 100 })
        XCTAssertFalse(recovered.routingEnabled(projectId: "project"))
        XCTAssertFalse(recovered.allowsCrossPlatform(projectId: "project"))
        try await recovered.ensure(projectId: "project", endpoints: endpoints, pairings: [remote.id: pairing],
            nativeEndpointId: "local", routingEnabled: true, allowCrossPlatform: true) { command, endpoint in
                recovered.receive(.init(sessionId: command.sessionId, projectId: command.projectId,
                    targetEndpointId: command.targetEndpointId, requestId: command.requestId,
                    revision: command.revision, accepted: true, generatedAt: 100), room: endpoint.room)
            }
        XCTAssertEqual(nativeGrants, 1)
        XCTAssertEqual(recovered.states["project"], .ready)
        XCTAssertTrue(recovered.routingEnabled(projectId: "project"))
        XCTAssertTrue(recovered.allowsCrossPlatform(projectId: "project"))
        XCTAssertEqual(saved?.writers, interrupted.writers)
        XCTAssertEqual(saved?.confirmedEndpoints, ["local", "remote"])
        XCTAssertNotEqual(saved?.commands.first?.requestId, interrupted.commands.first?.requestId)
    }

    func testRejectedNativeConfigurationCannotBecomeReadyOrLoseItsSavedPlan() async throws {
        let endpoint = ProjectNetworkEndpoint(id: "local", room: String(repeating: "a", count: 32),
            relayUrl: "wss://relay.test", publicKey: Data(repeating: 1, count: 32).base64EncodedString())
        var saved: ProjectNetworkPlan?
        let coordinator = ProjectNetworkCoordinator(load: { _ in nil }, save: { saved = $0 },
            nativeConfiguration: { command in
                .init(sessionId: command.sessionId, projectId: command.projectId,
                    targetEndpointId: command.targetEndpointId, requestId: command.requestId,
                    revision: command.revision, accepted: false, generatedAt: 100)
            }, clock: { 100 })
        do {
            try await coordinator.ensure(projectId: "project", endpoints: [endpoint], pairings: [:],
                nativeEndpointId: endpoint.id, send: { _, _ in XCTFail("Local configuration uses native transport.") })
            XCTFail("Rejected configuration must fail.")
        } catch { XCTAssertEqual(coordinator.states["project"], .failed) }
        XCTAssertEqual(saved?.projectId, "project")
        XCTAssertTrue(try XCTUnwrap(saved).confirmedEndpoints.isEmpty)
        do {
            try await coordinator.ensure(projectId: "project", endpoints: [endpoint], pairings: [:],
                requiredEndpoints: ["foreign"], nativeEndpointId: endpoint.id, send: { _, _ in XCTFail() })
            XCTFail("A foreign required computer must be refused.")
        } catch { XCTAssertEqual(coordinator.states["project"], .failed) }
    }

    func testAppModelRefusesMissingProjectRoutesButAllowsKeepingWorkOnTheSameComputer() async {
        let model = AppModel()
        model.demoMode = true
        var session = SessionInfo(sessionId: "session", agent: "codex", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        do {
            try await model.ensureProjectComputerNetwork(for: session, targetComputer: "remote")
            XCTFail("Unknown ownership cannot provision a network.")
        } catch {}
        session.projectId = "project"
        session.computerId = "local"
        do { try await model.ensureProjectComputerNetwork(for: session, targetComputer: "local") }
        catch { XCTFail("Continuing locally does not require a network grant.") }
        do {
            try await model.ensureProjectComputerNetwork(for: session, targetComputer: "remote")
            XCTFail("A missing Mesh snapshot cannot authorize another computer.")
        } catch {}
        XCTAssertNil(model.computerNetwork.states["project"])
    }
}

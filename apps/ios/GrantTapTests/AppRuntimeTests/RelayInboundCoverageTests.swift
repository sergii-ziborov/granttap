import XCTest
import TweetNacl
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testInboundPlainPayloadAllowlistDispatchesEverySupportedCallback() async throws {
        let client = RelayClient(pairing: testPairing(room: "inbound-room"))
        let callbacks = expectation(description: "all inbound callbacks")
        callbacks.expectedFulfillmentCount = 17
        var received = Set<String>()
        func mark(_ name: String) {
            received.insert(name)
            callbacks.fulfill()
        }
        client.onRequest = { _ in mark("request") }
        client.onDecision = { _ in mark("decision") }
        client.onApprovalCancel = { _ in mark("cancel") }
        client.onApprovalResolved = { _ in mark("resolved") }
        client.onApprovalsStatus = { _ in mark("status") }
        client.onAgentEvent = { _ in mark("event") }
        client.onSessions = { _ in mark("sessions") }
        client.onActivity = { _ in mark("activity") }
        client.onCapabilityUsage = { _ in mark("usage") }
        client.onCapabilityCatalog = { _ in mark("catalog") }
        client.onCompactResult = { _ in mark("compact") }
        client.onToolUpdateResult = { _ in mark("tool-update") }
        client.onMachineLoad = { _ in mark("load") }
        client.onMachineHeartbeat = { _ in mark("heartbeat") }
        client.onDeliveryReceipt = { _ in mark("receipt") }
        client.onMeshEvent = { _ in mark("mesh-event") }
        client.onMeshSnapshot = { _ in mark("mesh-snapshot") }

        for payload in try inboundAllowlistPayloads() {
            XCTAssertTrue(client.handlePlain(payload))
        }
        await fulfillment(of: [callbacks], timeout: 2)
        XCTAssertEqual(received.count, 17)
    }

    @MainActor
    func testInboundAcceptsMacMeshSnapshotWithModelCatalog() async throws {
        let client = RelayClient(pairing: testPairing(room: "mesh-catalog-room"))
        let accepted = expectation(description: "mac mesh snapshot")
        var received: ProjectMeshSnapshot?
        client.onMeshSnapshot = { snapshot in
            received = snapshot
            accepted.fulfill()
        }
        var snapshot = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 10
        )
        snapshot.execution = ProjectExecutionPolicy(
            mode: .distributed, revision: 1, hostGrantStatus: .none
        )
        snapshot.modelCatalog = [
            EndpointModelCatalog(endpointId: "Mac.lan", observedAt: 10, models: [],
                                 reason: "not_reported")
        ]
        XCTAssertTrue(client.handlePlain(try encoded(snapshot)))
        await fulfillment(of: [accepted], timeout: 2)
        XCTAssertEqual(received?.modelCatalog?.first?.reason, "not_reported")
        XCTAssertEqual(received?.execution?.mode, .distributed)
    }

    private func inboundAllowlistPayloads() throws -> [Data] {
        let request = ApprovalRequest(
            type: "approval.request", requestId: "r", agent: "codex",
            kind: "permission", tool: "Bash", title: "Run?", command: "npm test",
            cwd: "/repo", sessionId: "s", risk: .medium, danger: .caution,
            createdAt: 1
        )
        let decision = ApprovalDecision(
            type: "approval.decision", requestId: "r", decision: "allow",
            note: nil, decidedBy: "watch", sessionId: "s", decidedAt: 2
        )
        let cancel = ApprovalCancel(
            type: "approval.cancel", requestId: "r", cancelAll: false,
            reason: "closed", createdAt: 3
        )
        let resolved = ApprovalResolved(
            type: "approval.resolved", requestId: "r", status: "applied",
            decision: "allow", decidedBy: "phone", note: nil,
            sessionId: "s", nativeUiCleared: true, resolvedAt: 4
        )
        let status = ApprovalsStatus(
            type: "approvals.status", pending: [request], complete: false,
            covered: [ApprovalStatusScope(requestId: "r", sessionId: "s")],
            actions: nil, generatedAt: 5
        )
        let event = AgentEvent(
            type: "agent.event", text: "Done", requestId: nil,
            kind: "response", sessionId: "s", createdAt: 6
        )
        let activity = SessionActivity(
            sessionId: "s", agent: "codex", state: "working",
            entries: [ActivityEntry(id: "e", kind: "message", text: "Working", createdAt: 7)],
            generatedAt: 7
        )
        let compact = SessionCompactResult(
            type: "session.compact.result", sessionId: "s", ok: true,
            message: "Compacted", createdAt: 8
        )
        let toolUpdate = ToolUpdateResult(
            type: "tool.update.result", agent: "claude", requestId: "r", ok: true,
            before: "2.1.201", after: "2.1.260", command: "claude update",
            message: "Claude Code updated from 2.1.201 to 2.1.260.", output: "ok", createdAt: 8
        )
        let receipt = DeliveryReceipt(
            type: "delivery.receipt", messageId: "m", sessionId: "s",
            status: "accepted", error: nil, receivedAt: 9
        )
        let meshEvent = ProjectMeshEvent(
            type: "mesh.event", sessionId: "task", eventId: "progress",
            projectId: "project", taskId: "task", sourceSessionId: "s",
            eventType: "TASK_PROGRESS", createdAt: 10,
            payload: .init(summary: "Working")
        )
        let meshSnapshot = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "Project", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 10
        )
        return [
            try encoded(request), try encoded(decision), try encoded(cancel),
            try encoded(resolved), try encoded(status), try encoded(event),
            json(["type": "sessions.status", "machine": "Mac", "sessions": [],
                  "tokensRecent": 0, "tokenWindowHours": 12, "generatedAt": 10]),
            try encoded(activity),
            json(["type": "capability.usage.status", "events": [], "generatedAt": 11]),
            json(["type": "capability.catalog.status", "computerId": "c",
                  "machine": "Mac", "entries": [], "generatedAt": 12]),
            try encoded(compact), try encoded(toolUpdate),
            json(["type": "machine.load", "machine": "Mac",
                  "monitorCpuPercent": 1, "monitorMemoryBytes": 2,
                  "agents": [], "generatedAt": 13]),
            json(["type": "machine.heartbeat", "machine": "Mac", "createdAt": 14]),
            try encoded(receipt), try encoded(meshEvent), try encoded(meshSnapshot),
        ]
    }

    func testInboundRejectsUnknownReservedMalformedAndMissingCallbacks() throws {
        let client = RelayClient(pairing: testPairing(room: "reject-room"))
        XCTAssertFalse(client.handlePlain(Data()))
        XCTAssertFalse(client.handlePlain(json(["type": "unknown"])))
        XCTAssertFalse(client.handlePlain(json(["type": "session.key.grant"])))
        XCTAssertFalse(client.handlePlain(json(["type": "session.sealed"])))
        XCTAssertFalse(client.handlePlain(json([
            "type": "approval.request", "requestId": "missing-fields",
        ])))
        let event = AgentEvent(
            type: "agent.event", text: "No callback", requestId: nil,
            kind: "status", sessionId: nil, createdAt: 1
        )
        XCTAssertFalse(client.handlePlain(try encoded(event)))
        XCTAssertFalse(client.handlePlain(json([
            "type": "delivery.receipt", "messageId": "m",
            "status": "accepted", "receivedAt": 1,
        ])))
    }

    func testExactSessionScopeReplayCacheAndAckGuards() {
        XCTAssertFalse(RelayClient.hasExactSessionScope(Data(), sessionId: "s"))
        XCTAssertFalse(RelayClient.hasExactSessionScope(json(["sessionId": "s"]), sessionId: " "))
        XCTAssertFalse(RelayClient.hasExactSessionScope(json(["sessionId": " "]), sessionId: "s"))
        XCTAssertFalse(RelayClient.hasExactSessionScope(json(["sessionId": "other"]), sessionId: "s"))
        XCTAssertTrue(RelayClient.hasExactSessionScope(json(["sessionId": "s"]), sessionId: "s"))

        let client = RelayClient(pairing: testPairing(room: "cache-room"))
        client.rememberCiphertext("same")
        client.rememberCiphertext("same")
        XCTAssertEqual(client.seenCiphertextOrder, ["same"])
        for index in 0...RelayClient.maxSeenCiphertexts {
            client.rememberCiphertext("cipher-\(index)")
        }
        XCTAssertEqual(client.seenCiphertextOrder.count, RelayClient.maxSeenCiphertexts)
        XCTAssertFalse(client.seenCiphertexts.contains("same"))
        client.acknowledge(nil)
        client.acknowledge("delivery")
    }

    @MainActor
    func testEncryptedInboundAcceptsPlainGrantAndSessionSealedFrames() async throws {
        let phone = try NaclBox.keyPair()
        let machine = try NaclBox.keyPair()
        let room = String(repeating: "d", count: 32)
        let pairing = Pairing(
            relayUrl: "wss://relay.granttap.app", room: room, role: "phone",
            deviceName: "Phone", senderId: "phone",
            myPublicKey: phone.publicKey.base64EncodedString(),
            mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: machine.publicKey.base64EncodedString()
        )
        SessionKeyVault.remove(room: room)
        defer { SessionKeyVault.remove(room: room) }
        let client = RelayClient(pairing: pairing)
        let callbacks = expectation(description: "encrypted callbacks")
        callbacks.expectedFulfillmentCount = 2
        client.onAgentEvent = { _ in callbacks.fulfill() }

        let plain = try encoded(AgentEvent(
            type: "agent.event", text: "Plain", requestId: nil,
            kind: "response", sessionId: "session", createdAt: 1
        ))
        let envelope = try encryptedEnvelope(
            plain, pairing: pairing, machineSecret: machine.secretKey,
            deliveryId: "plain"
        )
        client.handle(envelope)
        client.handle(envelope)
        XCTAssertEqual(client.seenCiphertextOrder.count, 1)

        let transferKey = base64URL(Data(repeating: 5, count: 32))
        let grant = try encoded(SessionKeyGrant(
            type: "session.key.grant", sessionId: "session",
            key: transferKey, createdAt: 2
        ))
        client.handle(try encryptedEnvelope(
            grant, pairing: pairing, machineSecret: machine.secretKey,
            deliveryId: "grant"
        ))
        XCTAssertEqual(client.sessionKeys["session"], transferKey)

        let inner = try encoded(AgentEvent(
            type: "agent.event", text: "Sealed", requestId: nil,
            kind: "response", sessionId: "session", createdAt: 3
        ))
        let box = try XCTUnwrap(Crypto.openableSeal(inner, key: transferKey))
        let wrapper = try encoded(SessionSealed(
            type: "session.sealed", sessionId: "session",
            nonce: box.nonce, box: box.box, createdAt: 3
        ))
        client.handle(try encryptedEnvelope(
            wrapper, pairing: pairing, machineSecret: machine.secretKey,
            deliveryId: "sealed"
        ))
        await fulfillment(of: [callbacks], timeout: 2)
        XCTAssertEqual(client.seenCiphertextOrder.count, 3)
    }

    func testEncryptedInboundRejectsUnauthenticatedEnvelopeVariants() throws {
        let phone = try NaclBox.keyPair()
        let machine = try NaclBox.keyPair()
        let pairing = Pairing(
            relayUrl: "wss://relay.granttap.app",
            room: String(repeating: "e", count: 32), role: "phone",
            deviceName: "Phone", senderId: "phone",
            myPublicKey: phone.publicKey.base64EncodedString(),
            mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: machine.publicKey.base64EncodedString()
        )
        let client = RelayClient(pairing: pairing)
        let plain = json(["type": "unknown"])
        let sealed = try Crypto.seal(
            plain, theirPublicKeyB64: pairing.myPublicKey,
            mySecretKeyB64: machine.secretKey.base64EncodedString()
        )
        let base = Envelope(
            room: pairing.room, from: .machine, to: "phone", senderId: "machine",
            deliveryId: "id", nonce: sealed.nonce, box: sealed.box
        )
        var variants = [base]
        variants[0].v = 0
        var wrongRoom = base; wrongRoom.room = "wrong"; variants.append(wrongRoom)
        var wrongRole = base; wrongRole.from = .phone; variants.append(wrongRole)
        var wrongTarget = base; wrongTarget.to = "machine"; variants.append(wrongTarget)
        var expired = base; expired.expiresAt = 1; variants.append(expired)
        var corrupt = base; corrupt.box = "bad"; variants.append(corrupt)
        for value in variants {
            client.handle(String(decoding: try JSONEncoder().encode(value), as: UTF8.self))
        }
        client.handle("not json")
        XCTAssertTrue(client.seenCiphertextOrder.isEmpty)
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func encryptedEnvelope(
        _ plain: Data, pairing: Pairing, machineSecret: Data,
        deliveryId: String
    ) throws -> String {
        let sealed = try Crypto.seal(
            plain, theirPublicKeyB64: pairing.myPublicKey,
            mySecretKeyB64: machineSecret.base64EncodedString()
        )
        let envelope = Envelope(
            room: pairing.room, from: .machine, to: "phone", senderId: "machine",
            deliveryId: deliveryId, nonce: sealed.nonce, box: sealed.box
        )
        return String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testConnectionRegistryPersistsPrefersAndUnlinksWithoutCrossRoomLeakage() {
        let stored = PairedConnectionStore.load()
        PairedConnectionStore.removeAll()
        defer {
            PairedConnectionStore.removeAll()
            if !stored.connections.isEmpty { _ = PairedConnectionStore.save(stored) }
        }
        let model = AppModel()
        model.loadConnectionRegistry()
        XCTAssertTrue(model.connectionRegistry.connections.isEmpty)
        XCTAssertFalse(model.addConnection(testPairing()))

        let first = coveragePairing(label: "a", name: "First Mac")
        let second = coveragePairing(label: "b", name: "Second Mac")
        XCTAssertTrue(model.addConnection(first))
        XCTAssertTrue(model.addConnection(second, prefer: false))
        XCTAssertEqual(model.connectionRegistry.connections.count, 2)
        XCTAssertEqual(model.connectionRegistry.preferredId, first.room)
        model.persistConnectionRegistry()
        model.setPreferredConnection(roomId: "missing")
        model.setPreferredConnection(roomId: second.room)
        XCTAssertEqual(model.connectionRegistry.preferredId, second.room)

        let requestId = "unlink-\(UUID().uuidString)"
        let request = ApprovalRequest(
            type: "approval.request", requestId: requestId, agent: "codex",
            kind: "permission", tool: "Bash", title: "Run?", command: nil,
            cwd: nil, sessionId: "session", risk: .medium, danger: .caution,
            createdAt: Date().timeIntervalSince1970 * 1_000
        )
        model.pending = [request]
        model.questions = [AgentEvent(
            type: "agent.event", text: "Proceed?", requestId: requestId,
            kind: "question", sessionId: "session", createdAt: 1
        )]
        model.requestSourceRoom[requestId] = first.room
        model.focusedApprovalId = requestId
        var delivery = existingSessionDelivery(
            createdAt: 1, id: "unlink-delivery", sessionId: "session"
        )
        delivery.roomId = first.room
        delivery.state = .sending
        model.deliveries = [delivery]
        model.unlinkConnection(roomId: first.room)
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertTrue(model.questions.isEmpty)
        XCTAssertNil(model.focusedApprovalId)
        XCTAssertEqual(model.deliveries.first?.state, .failed)
        XCTAssertEqual(model.connectionRegistry.connections.map(\.id), [second.room])

        model.unlinkConnection(roomId: second.room)
        XCTAssertTrue(model.connectionRegistry.connections.isEmpty)
        XCTAssertNil(model.pairing)
        XCTAssertTrue(model.sessions.isEmpty)
        for client in model.relaysByRoom.values { client.disconnect() }
    }

    @MainActor
    func testAttachedRelayCallbacksStayBoundToTheirAuthenticatedRoom() {
        let stored = PairedConnectionStore.load()
        defer {
            PairedConnectionStore.removeAll()
            if !stored.connections.isEmpty { _ = PairedConnectionStore.save(stored) }
            CapabilityUsageStore.shared.clear()
            ProjectGovernancePersistence.clear()
        }
        let model = AppModel()
        model.projectGovernance = [:]
        model.pendingProjectPolicyRevisions = [:]
        let pairing = coveragePairing(label: "c", name: "Callback Mac")
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        model.attachRelay(for: pairing)
        guard let client = model.relaysByRoom[pairing.room] else {
            return XCTFail("relay was not attached")
        }
        model.relay = client
        let sessionId = "callback-session"
        model.rememberSessionSourceRoom(pairing.room, sessionId: sessionId)
        let now = Date().timeIntervalSince1970 * 1_000

        client.onConnectionChange?(true)
        XCTAssertTrue(model.roomRuntime[pairing.room]?.socketUp == true)
        client.onMachineHeartbeat?(MachineHeartbeat(machine: "Callback Mac", createdAt: now))
        client.onMachineLoad?(MachineLoad(
            machine: "Callback Mac", monitorCpuPercent: 1, monitorMemoryBytes: 2,
            agents: [], generatedAt: now
        ))
        XCTAssertNotNil(model.machineLoadByRoom[pairing.room])

        let request = ApprovalRequest(
            type: "approval.request", requestId: "callback-request", agent: "codex",
            kind: "permission", tool: "Bash", title: "Run?", command: nil,
            cwd: nil, sessionId: sessionId, risk: .low, danger: .safe, createdAt: now
        )
        client.onRequest?(request)
        client.onDecision?(ApprovalDecision(
            type: "approval.decision", requestId: request.requestId, decision: "allow",
            note: nil, decidedBy: "watch", sessionId: sessionId, decidedAt: now
        ))
        client.onApprovalsStatus?(ApprovalsStatus(
            type: "approvals.status", pending: [request], complete: false,
            covered: [ApprovalStatusScope(requestId: request.requestId, sessionId: sessionId)],
            actions: nil, generatedAt: now + 1
        ))
        client.onAgentEvent?(AgentEvent(
            type: "agent.event", text: "Working", requestId: nil,
            kind: "status", sessionId: sessionId, createdAt: now
        ))
        client.onActivity?(SessionActivity(
            sessionId: sessionId, agent: "codex", state: "working",
            entries: [ActivityEntry(id: "a", kind: "message", text: "Working", createdAt: now)],
            generatedAt: now
        ))
        XCTAssertEqual(model.activities[sessionId]?.entries.count, 1)

        client.onCapabilityUsage?(CapabilityUsageStatus(
            type: "capability.usage.status", events: [], generatedAt: now
        ))
        client.onCapabilityCatalog?(CapabilityCatalogStatus(
            type: "capability.catalog.status", computerId: "ignored",
            machine: "Callback Mac", entries: [], generatedAt: now
        ))
        client.onSessions?(SessionsStatus(
            machine: "Callback Mac", sessions: [], tokensRecent: 0,
            tokenWindowHours: 12, generatedAt: now + 2
        ))
        model.agentMeshPreferences.meshEnabled = true
        client.onProjectPolicyStatus?(ProjectGovernanceFixtures.status())
        client.onProjectPolicyAck?(ProjectGovernanceFixtures.acknowledgement())
        XCTAssertEqual(model.projectGovernance["project"]?.revision, 3)
        client.onDeliveryReceipt?(DeliveryReceipt(
            type: "delivery.receipt", messageId: "missing", sessionId: sessionId,
            status: "accepted", error: nil, receivedAt: now
        ))
        model.compactingSessions.insert(sessionId)
        client.onCompactResult?(SessionCompactResult(
            type: "session.compact.result", sessionId: sessionId, ok: true,
            message: "Compacted", createdAt: now
        ))
        XCTAssertNotNil(model.compactResults[sessionId])

        client.onApprovalResolved?(ApprovalResolved(
            type: "approval.resolved", requestId: request.requestId, status: "applied",
            decision: "allow", decidedBy: "phone", note: nil, sessionId: sessionId,
            nativeUiCleared: true, resolvedAt: now + 3
        ))
        client.onApprovalCancel?(ApprovalCancel(
            type: "approval.cancel", requestId: nil, cancelAll: false,
            reason: nil, createdAt: now
        ))
        client.onConnectionChange?(false)
        XCTAssertFalse(model.roomRuntime[pairing.room]?.socketUp == true)
        client.disconnect()
    }

    @MainActor
    func testSecondaryRelayConnectionChangeDoesNotReplacePreferredState() {
        let model = AppModel()
        let first = coveragePairing(label: "d", name: "Preferred")
        let second = coveragePairing(label: "e", name: "Secondary")
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            ConnectionRegistryLogic.upsert(.empty, pairing: first),
            pairing: second, prefer: false
        )
        let preferred = RelayClient(pairing: first)
        let secondary = RelayClient(pairing: second)
        model.relay = preferred
        model.relaysByRoom = [first.room: preferred, second.room: secondary]
        model.applyRoomConnectionChange(true, client: secondary)
        XCTAssertTrue(model.roomRuntime[second.room]?.socketUp == true)
        XCTAssertFalse(model.connected)
        model.applyRoomConnectionChange(false, client: secondary)
        XCTAssertFalse(model.roomRuntime[second.room]?.socketUp == true)
    }

    func coveragePairing(label: Character, name: String) -> Pairing {
        let key = Data(repeating: UInt8(label.asciiValue ?? 7), count: 32)
            .base64EncodedString()
        return Pairing(
            relayUrl: "ws://127.0.0.1:1", room: String(repeating: label, count: 32),
            role: "phone", deviceName: name, senderId: "coverage-\(label)",
            myPublicKey: key, mySecretKey: key, peerPublicKey: key
        )
    }
}

import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    func testStaleMacCatalogRefreshRequiresSocketRecovery() {
        XCTAssertTrue(ConnectionSnapshot.shouldRecoverCatalogLink(for: .macOffline))
        XCTAssertTrue(ConnectionSnapshot.shouldRecoverCatalogLink(for: .needRepair))
        XCTAssertTrue(ConnectionSnapshot.shouldRecoverCatalogLink(for: .phoneOffline))
        XCTAssertFalse(ConnectionSnapshot.shouldRecoverCatalogLink(for: .live))
        XCTAssertFalse(ConnectionSnapshot.shouldRecoverCatalogLink(for: .notLinked))
        XCTAssertFalse(ConnectionSnapshot.shouldRecoverCatalogLink(for: .demo))
    }

    @MainActor
    func testForegroundRecoveryDetectsAStaleCatalogEvenWhenSocketLooksOpen() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        let room = "foreground-stale-room"
        var registry = ConnectionRegistryLogic.upsert(
            .empty,
            pairing: testPairing(room: room),
            prefer: true,
            now: now - 120_000
        )
        registry = ConnectionRegistryLogic.noteCatalog(
            registry,
            roomId: room,
            generatedAt: now - 100_000,
            machineName: "stale.local"
        )
        model.connectionRegistry = registry
        model.roomRuntime[room] = AppModel.RoomRuntime(
            socketUp: true,
            socketUpSince: now - 120_000
        )

        XCTAssertEqual(model.connectionSnapshot.phase, .macOffline)
        XCTAssertTrue(model.needsForegroundCatalogRecovery)
    }

    func testHostedXCTestIsDetectedBeforeProductionBootstrap() {
        XCTAssertTrue(AppRuntime.isRunningUnitTests)
    }

    func testExplicitSocketReplacementEmitsOnlyOneDownEdge() {
        let pairing = Pairing(
            relayUrl: "ws://127.0.0.1:1",
            room: "socket-replacement-room",
            role: "phone",
            deviceName: "Test phone",
            senderId: "test-sender",
            myPublicKey: "test-public",
            mySecretKey: "test-secret",
            peerPublicKey: "test-peer"
        )
        let client = RelayClient(pairing: pairing)
        client.task = URLSession(configuration: .ephemeral).webSocketTask(
            with: URL(string: "ws://127.0.0.1:1/ws")!
        )
        var edges: [Bool] = []
        client.onConnectionChange = { edges.append($0) }

        client.interruptSocketForReplacement()
        client.interruptSocketForReplacement()

        XCTAssertEqual(edges, [false])
        XCTAssertNil(client.task)
    }

    @MainActor
    func testGrokBuildPermissionUsesNormalAllowDenyClassification() {
        let request = ApprovalRequest(
            type: "approval.request",
            requestId: "grok-permission",
            agent: "Grok Build",
            kind: "permission",
            tool: "ask_yes_no",
            title: "Allow this Grok tool?",
            command: nil,
            cwd: "/repo",
            sessionId: "shared-native-id",
            risk: .medium,
            danger: .caution,
            createdAt: 1
        )

        XCTAssertFalse(AppModel().isMcpAskApproval(request))
    }

    @MainActor
    func testWatchIntegrationChangeIsNotSuppressedAsDuplicateState() {
        let before = WatchState(agents: [
            WatchAgentIntegration(agent: "grok", installed: false, hookConfigured: false),
        ])
        let after = WatchState(agents: [
            WatchAgentIntegration(agent: "grok", installed: true, hookConfigured: true),
        ])

        XCTAssertFalse(WatchBridge.hasSameMeaningfulState(before, after))
        XCTAssertTrue(WatchBridge.hasSameMeaningfulState(before, before))
    }

    @MainActor
    func testFollowUpWireMessageCarriesPersistedProviderAgent() {
        let model = AppModel()
        model.sessions = [
            SessionInfo(
                sessionId: "shared-native-id",
                agent: "codex",
                state: "idle",
                startedAt: 1,
                lastActivityAt: 2,
                tokensSession: 0,
                tokensLastTurn: 0
            ),
            SessionInfo(
                sessionId: "shared-native-id",
                agent: "grok",
                state: "idle",
                startedAt: 1,
                lastActivityAt: 2,
                tokensSession: 0,
                tokensLastTurn: 0
            ),
        ]
        let delivery = existingSessionDelivery(
            createdAt: 3,
            sessionId: "shared-native-id",
            agent: "Grok Build"
        )

        let payload = model.wireUserMessage(for: delivery)

        XCTAssertEqual(payload.sessionId, "shared-native-id")
        XCTAssertEqual(payload.agent, "grok")
    }

    @MainActor
    func testPermissionFollowUpIsAnOrdinaryProviderMessage() throws {
        let action = try XCTUnwrap(WatchAction.permissionFollowUp(
            "Use the safer command instead",
            sessionId: "shared-native-id",
            agent: "Grok Build"
        ))
        let delivery = existingSessionDelivery(
            createdAt: 3,
            text: action.text ?? "",
            sessionId: action.sessionId ?? "",
            agent: action.agent,
            requestId: action.requestId
        )

        let payload = AppModel().wireUserMessage(for: delivery)

        XCTAssertEqual(action.kind, .message)
        XCTAssertNil(action.requestId)
        XCTAssertEqual(action.agent, "grok")
        XCTAssertEqual(payload.sessionId, "shared-native-id")
        XCTAssertNil(payload.requestId)
        XCTAssertEqual(payload.agent, "grok")
    }

    func testPermissionFollowUpWithoutScopedSessionFailsClosed() {
        XCTAssertFalse(WatchAction.canSendPermissionFollowUp(sessionId: nil))
        XCTAssertFalse(WatchAction.canSendPermissionFollowUp(sessionId: " \n "))
        XCTAssertTrue(WatchAction.canSendPermissionFollowUp(sessionId: "session-1"))
        XCTAssertNil(WatchAction.permissionFollowUp(
            "Do something else",
            sessionId: nil,
            agent: "grok"
        ))
    }

    @MainActor
    func testWatchQuestionReplyRemainsCorrelated() {
        let action = WatchAction.questionReply(
            "Use option B",
            sessionId: "shared-native-id",
            requestId: "mcp-question-1"
        )
        let delivery = existingSessionDelivery(
            createdAt: 3,
            text: action.text ?? "",
            sessionId: action.sessionId ?? "",
            agent: action.agent,
            requestId: action.requestId
        )

        let payload = AppModel().wireUserMessage(for: delivery)

        XCTAssertEqual(action.kind, .message)
        XCTAssertEqual(action.requestId, "mcp-question-1")
        XCTAssertNil(action.agent)
        XCTAssertEqual(payload.sessionId, "shared-native-id")
        XCTAssertEqual(payload.requestId, "mcp-question-1")
        XCTAssertNil(payload.agent)
    }

    func testConnectionSnapshotCopyCoversEveryPersonalHealthPhase() {
        let phases: [ConnectionPhase] = [
            .demo, .notLinked, .phoneOffline, .macOffline, .needRepair, .live,
        ]
        for phase in phases {
            let snapshot = ConnectionSnapshot(
                phase: phase, linked: phase != .notLinked,
                deviceName: "Phone", machineName: phase == .live ? "Mac" : nil,
                roomShort: "abcd", catalogAgeSeconds: 4
            )
            XCTAssertFalse(snapshot.statusTitle.isEmpty)
            XCTAssertFalse(snapshot.detail.isEmpty)
            XCTAssertFalse(snapshot.primaryActionTitle.isEmpty)
            XCTAssertFalse(snapshot.footer.isEmpty)
            _ = snapshot.statusColor
            XCTAssertEqual(snapshot.showsPairEntry, phase != .demo)
        }
        XCTAssertTrue(ConnectionSnapshot(
            phase: .live, linked: true, deviceName: nil, machineName: nil,
            roomShort: nil, catalogAgeSeconds: nil
        ).detail.contains("sync"))
        XCTAssertTrue(ConnectionSnapshot.needsAttention(.phoneOffline))
        XCTAssertTrue(ConnectionSnapshot.needsAttention(.macOffline))
        XCTAssertTrue(ConnectionSnapshot.needsAttention(.needRepair))
        XCTAssertFalse(ConnectionSnapshot.needsAttention(.live))
    }

    @MainActor
    func testConnectionHealthDerivesDemoFreshnessAgeAndSafeFixBranches() async {
        let model = AppModel()
        model.startDemo()
        XCTAssertEqual(model.connectionSnapshot.phase, .demo)
        XCTAssertFalse(model.needsForegroundCatalogRecovery)
        await model.fixConnection()
        XCTAssertFalse(model.demoMode)
        XCTAssertEqual(model.connectionSnapshot.phase, .notLinked)
        await model.fixConnection()
        model.recoverCatalogAfterForeground()

        XCTAssertFalse(model.isMacCatalogFresh)
        XCTAssertNil(model.catalogAgeSeconds)
        model.lastSessionsGeneratedAt = Date().timeIntervalSince1970 * 1_000 + 1_000
        XCTAssertFalse(model.isMacCatalogFresh)
        XCTAssertEqual(model.catalogAgeSeconds, 0)
        model.lastSessionsGeneratedAt = Date().timeIntervalSince1970 * 1_000 - 1_000
        XCTAssertTrue(model.isMacCatalogFresh)
        XCTAssertNotNil(model.catalogAgeSeconds)
    }

}

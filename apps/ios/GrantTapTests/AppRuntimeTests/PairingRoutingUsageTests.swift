import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    func testPairingMailboxUnavailableExplainsExpiryWithoutMislabelingAccessErrors() {
        for status in [404, 410] {
            let error = PairingError.forHTTPStatus(status)
            guard case .codeExpiredOrUsed = error else {
                XCTFail("HTTP \(status) must be classified as an expired or used pairing code")
                continue
            }
            XCTAssertEqual(
                error.message,
                "This QR expired or was already used. Authenticate again and scan the new QR on granttap.com/connect."
            )
        }

        for status in [401, 403] {
            guard case .relayError(let actual) = PairingError.forHTTPStatus(status) else {
                XCTFail("HTTP \(status) must remain a relay access error")
                continue
            }
            XCTAssertEqual(actual, status)
        }
    }

    @MainActor
    func testSecondaryCatalogNeverOverridesFreshlySelectedComputer() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        var registry = ConnectionRegistryLogic.upsert(
            .empty,
            pairing: testPairing(room: "room-old", deviceName: "Old Mac"),
            prefer: true,
            now: now - 2_000
        )
        registry = ConnectionRegistryLogic.upsert(
            registry,
            pairing: testPairing(room: "room-selected", deviceName: "Selected Mac"),
            prefer: true,
            now: now - 1_000
        )
        model.connectionRegistry = registry

        model.applySessionsStatus(
            SessionsStatus(
                machine: "old.local",
                sessions: [],
                tokensRecent: 0,
                tokenWindowHours: 12,
                generatedAt: now
            ),
            fromRoom: "room-old"
        )

        XCTAssertEqual(model.connectionRegistry.preferredId, "room-selected")
        XCTAssertEqual(model.pairing?.room, "room-selected")
    }

    @MainActor
    func testOlderCatalogSnapshotCannotRollBackConnectionFreshness() throws {
        let model = AppModel()
        let room = "room-watermark"
        var registry = ConnectionRegistryLogic.upsert(
            .empty,
            pairing: testPairing(room: room),
            prefer: true,
            now: 1_000
        )
        registry = ConnectionRegistryLogic.noteCatalog(
            registry,
            roomId: room,
            generatedAt: 3_000,
            machineName: "fresh.local"
        )
        model.connectionRegistry = registry
        model.lastSessionsGeneratedAt = 3_000

        model.applySessionsStatus(
            SessionsStatus(
                machine: "stale.local",
                sessions: [],
                tokensRecent: 1,
                tokenWindowHours: 12,
                generatedAt: 2_000
            ),
            fromRoom: room
        )

        let connection = try XCTUnwrap(model.connectionRegistry.connections.first)
        XCTAssertEqual(connection.lastCatalogAt, 3_000)
        XCTAssertEqual(connection.lastMachineName, "fresh.local")
        XCTAssertEqual(model.lastSessionsGeneratedAt, 3_000)
    }

    @MainActor
    func testChatRoutePinsExistingChatAndUsesPreferredComputerForNewTask() throws {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        var registry = ConnectionRegistryLogic.upsert(
            .empty,
            pairing: testPairing(room: "room-a", deviceName: "Office Mac"),
            prefer: false,
            now: now - 2_000
        )
        registry = ConnectionRegistryLogic.upsert(
            registry,
            pairing: testPairing(room: "room-b", deviceName: "Studio PC"),
            prefer: true,
            now: now - 1_000
        )
        registry = ConnectionRegistryLogic.noteCatalog(
            registry,
            roomId: "room-b",
            generatedAt: now,
            machineName: "studio.local"
        )
        model.connectionRegistry = registry
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: false, socketUpSince: 0)
        model.roomRuntime["room-b"] = AppModel.RoomRuntime(socketUp: true, socketUpSince: now)
        model.rememberSessionSourceRoom("room-a", sessionId: "existing-chat")

        let existing = try XCTUnwrap(model.chatComputerRoute(forSessionId: "existing-chat"))
        let newTask = try XCTUnwrap(model.chatComputerRoute(forSessionId: nil))

        XCTAssertEqual(existing.roomId, "room-a")
        XCTAssertEqual(existing.computerName, "Office Mac")
        XCTAssertEqual(existing.phase, .phoneOffline)
        XCTAssertEqual(newTask.roomId, "room-b")
        XCTAssertEqual(newTask.computerName, "studio.local")
        XCTAssertEqual(newTask.phase, .live)
    }

    @MainActor
    func testNewTaskDeliveryPinsExplicitComputerInsteadOfPreferredComputer() throws {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        var registry = ConnectionRegistryLogic.upsert(
            .empty,
            pairing: testPairing(room: "room-preferred", deviceName: "Preferred Mac"),
            prefer: true,
            now: now - 2_000
        )
        registry = ConnectionRegistryLogic.upsert(
            registry,
            pairing: testPairing(room: "room-selected", deviceName: "Selected PC"),
            prefer: false,
            now: now - 1_000
        )
        model.connectionRegistry = registry
        model.deliveries = []

        model.sendMessage(
            "route this exactly",
            agent: "codex",
            roomId: "room-selected"
        )

        let delivery = try XCTUnwrap(model.deliveries.first)
        XCTAssertEqual(delivery.roomId, "room-selected")
        XCTAssertEqual(model.connectionRegistry.preferredId, "room-preferred")
        let stub = try XCTUnwrap(delivery.sessionId)
        XCTAssertEqual(model.sourceRoom(forSessionId: stub), "room-selected")
    }

    func testRoutingPresentationNamesProviderComputerAndHonestQueueState() {
        let online = ChatComputerRoute(
            roomId: "room-a",
            computerName: "Main Mac",
            phase: .live
        )
        let offline = ChatComputerRoute(
            roomId: "room-a",
            computerName: "Main Mac",
            phase: .phoneOffline
        )
        var delivery = existingSessionDelivery(createdAt: 1, agent: "codex")
        delivery.state = .queued
        delivery.attempts = 0

        XCTAssertEqual(
            TaskRoutePresentation.sessionMetadata(
                agent: "codex",
                model: "gpt-5.6-sol",
                project: "nodvox",
                route: online
            ),
            "nodvox · Codex · gpt-5.6-sol · Main Mac · Online"
        )
        XCTAssertEqual(
            TaskRoutePresentation.deliveryStatus(delivery, route: offline),
            "Queued until Main Mac reconnects"
        )
        XCTAssertEqual(
            TaskRoutePresentation.deliveryStatus(delivery, route: online),
            "Queued · attempt 0 of 5"
        )
        XCTAssertNil(TaskRoutePresentation.allowedCount([]))
        XCTAssertEqual(TaskRoutePresentation.allowedCount([true, false, true]), 2)
        XCTAssertNil(TaskRoutePresentation.providerUnavailableReason("cursor"))
        XCTAssertNil(TaskRoutePresentation.providerUnavailableReason("codex"))
        XCTAssertNil(TaskRoutePresentation.providerUnavailableReason("grok"))
    }

    func testCapabilityUsageWireRetainsProviderAndModelIdentity() throws {
        let event = RemoteCapabilityUsageEvent(
            sourceId: "session:call",
            roomId: "room-a",
            sessionId: "session",
            agent: "grok",
            model: "grok-4.5",
            kind: .mcp,
            name: "ccd_session",
            toolName: "mcp__ccd_session__spawn_task",
            createdAt: 1,
            resource: CapabilityResourceUsage(
                attribution: .measured, cpuTimeMs: 24,
                peakRssBytes: 112_000_000, processCount: 3,
                sampleWindowMs: 218
            )
        )

        let decoded = try JSONDecoder().decode(
            RemoteCapabilityUsageEvent.self,
            from: JSONEncoder().encode(event)
        )

        XCTAssertEqual(decoded.agent, "grok")
        XCTAssertEqual(decoded.model, "grok-4.5")
        XCTAssertEqual(decoded.resource?.attribution, .measured)
        XCTAssertEqual(decoded.resource?.peakRssBytes, 112_000_000)
        XCTAssertEqual(decoded.resource?.cpuTimeMs, 24)

        let legacy = try JSONDecoder().decode(
            RemoteCapabilityUsageEvent.self,
            from: Data("""
                {"sourceId":"legacy","kind":"cli","name":"git","toolName":"git","createdAt":1}
                """.utf8)
        )
        XCTAssertNil(legacy.resource)
    }

    func testCapabilityUsageGroupingSeparatesSameToolAcrossProvidersAndModels() {
        let grok = CapabilityUsageGrouping.key(
            agent: "grok", model: "grok-4.5", kind: .mcp, name: "ccd_session"
        )
        let cursor = CapabilityUsageGrouping.key(
            agent: "cursor", model: "composer-2", kind: .mcp, name: "ccd_session"
        )
        let otherGrokModel = CapabilityUsageGrouping.key(
            agent: "grok", model: "grok-5", kind: .mcp, name: "ccd_session"
        )

        XCTAssertNotEqual(grok, cursor)
        XCTAssertNotEqual(grok, otherGrokModel)
    }

}

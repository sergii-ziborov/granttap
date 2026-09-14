import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testRoomOwnershipResolutionAndRelayRoutingFailClosed() {
        let model = AppModel()
        let firstRoom = "first-\(UUID().uuidString)"
        let secondRoom = "second-\(UUID().uuidString)"
        let sessionId = "native-\(UUID().uuidString)"
        let resolvedId = "resolved-\(UUID().uuidString)"
        let first = RelayClient(pairing: testPairing(room: firstRoom))
        let second = RelayClient(pairing: testPairing(room: secondRoom))
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            ConnectionRegistryLogic.upsert(
                .empty, pairing: testPairing(room: firstRoom), prefer: true
            ), pairing: testPairing(room: secondRoom), prefer: false
        )
        model.relaysByRoom = [firstRoom: first, secondRoom: second]
        model.sessionIdAliases[sessionId] = resolvedId

        model.rememberSessionSourceRooms("", sessionIds: [sessionId])
        model.rememberSessionSourceRooms(firstRoom, sessionIds: ["  ", sessionId])
        XCTAssertEqual(model.sessionRoomOwnership(forSessionId: sessionId), .exact(firstRoom))
        XCTAssertEqual(model.sourceRoom(forSessionId: resolvedId), firstRoom)
        XCTAssertTrue(model.acceptsSessionPayload(sessionId: sessionId, fromRoom: firstRoom))
        XCTAssertFalse(model.acceptsSessionPayload(sessionId: sessionId, fromRoom: secondRoom))
        XCTAssertTrue(model.relayForSession(sessionId) === first)

        model.rememberSessionSourceRoom(secondRoom, sessionId: sessionId)
        guard case .ambiguous = model.sessionRoomOwnership(forSessionId: sessionId) else {
            return XCTFail("two authenticated rooms must be ambiguous")
        }
        XCTAssertFalse(model.acceptsSessionPayload(sessionId: sessionId, fromRoom: firstRoom))
        XCTAssertNil(model.relayForSession(sessionId))
        XCTAssertNil(model.sourceRoom(forSessionId: sessionId))
        XCTAssertEqual(model.sessionRoomOwnership(forSessionId: " "), .unknown)

        model.sessionSourceRooms = [:]
        XCTAssertTrue(model.acceptsSessionPayload(sessionId: "legacy", fromRoom: firstRoom))
        XCTAssertNil(model.relayForSession("legacy"))
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: firstRoom)
        )
        XCTAssertTrue(model.relayForSession("legacy") === first)
        XCTAssertEqual(model.sourceRoom(forSessionId: "legacy"), firstRoom)
    }

    @MainActor
    func testRoomMapsRebuildFromLinkedDeliveriesAndClientIdentity() {
        let model = AppModel()
        let room = "rebuild-\(UUID().uuidString)"
        let removedRoom = "removed-\(UUID().uuidString)"
        let client = RelayClient(pairing: testPairing(room: room))
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: room)
        )
        model.relaysByRoom[room] = client
        model.sessionIdAliases["stub"] = "native"
        model.sessionSourceRooms = [
            "kept": [room], "removed": [removedRoom], "stub": [removedRoom],
        ]
        var delivery = existingSessionDelivery(
            createdAt: 10, id: "route-delivery", sessionId: "stub"
        )
        delivery.roomId = room
        delivery.state = .failed
        model.deliveries = [delivery]

        model.pruneSessionSourceRoomsToLinkedRooms()
        XCTAssertEqual(model.sessionSourceRooms["kept"], [room])
        XCTAssertEqual(model.sessionSourceRooms["stub"], [room])
        XCTAssertEqual(model.sessionSourceRooms["native"], [room])
        XCTAssertNil(model.sessionSourceRooms["removed"])
        XCTAssertEqual(model.roomId(for: client), room)
        XCTAssertNil(model.roomId(for: RelayClient(pairing: testPairing(room: "none"))))

        model.remapSessionSourceRooms(from: "stub", to: "mapped")
        XCTAssertEqual(model.sessionSourceRooms["mapped"], [room])
        model.resetSessionSourceRoomsForCatalogSwitch()
        XCTAssertNil(model.sessionSourceRooms["kept"])
        XCTAssertEqual(model.sessionSourceRooms["stub"], [room])

        model.deliveries[0].state = .delivered
        model.localOnlySessionIds = []
        model.resetSessionSourceRoomsForCatalogSwitch()
        XCTAssertTrue(model.sessionSourceRooms.isEmpty)
    }

    @MainActor
    func testApprovalRoutingConvergenceAndDecisionScopesAreBounded() {
        let model = AppModel()
        let scope = UUID().uuidString
        let room = "room-\(scope)"
        let request = "request-\(scope)"
        model.rememberRequestSourceRoom("", requestId: request)
        model.rememberRequestSourceRoom(room, requestId: request)
        XCTAssertTrue(model.requestBelongsToSource(request, room: room))
        XCTAssertFalse(model.requestBelongsToSource(request, room: nil))
        XCTAssertFalse(model.requestBelongsToSource(request, room: "wrong"))
        model.forgetRequestSourceRoom(request)
        XCTAssertTrue(model.requestBelongsToSource(request, room: nil))

        XCTAssertNil(AppModel.normalizedApprovalSession("  "))
        XCTAssertEqual(AppModel.normalizedApprovalSession(" chat "), "chat")
        XCTAssertTrue(AppModel.approvalScopeKey(request, sessionId: nil).contains(request))
        XCTAssertTrue(model.cancellationKey(request, room: nil).hasPrefix("legacy|"))

        let now = Date().timeIntervalSince1970 * 1_000
        model.approvalTerminalTombstones = [
            "old": now - AppModel.approvalTombstoneRetentionMs - 1,
            "new": now,
        ]
        model.pruneApprovalTerminalTombstones(nowMs: now)
        XCTAssertEqual(Set(model.approvalTerminalTombstones.keys), ["new"])
        model.markApprovalTerminal(request, room: room, sessionId: "chat")
        XCTAssertTrue(model.wasApprovalTerminal(request, room: room, sessionId: "chat"))
        XCTAssertFalse(model.wasApprovalTerminal(request, room: room, sessionId: "other"))

        XCTAssertFalse(model.acceptApprovalStatusWatermark(.nan, room: room))
        XCTAssertFalse(model.acceptApprovalStatusWatermark(0, room: room))
        XCTAssertTrue(model.acceptApprovalStatusWatermark(10, room: room))
        XCTAssertFalse(model.acceptApprovalStatusWatermark(10, room: room))
        model.clearApprovalConvergenceState(forRoom: room)
        XCTAssertNil(model.approvalStatusWatermarkByRoom[room])
        model.clearApprovalConvergenceState()
        XCTAssertTrue(model.approvalTerminalTombstones.isEmpty)

        model.markDecisionInFlight(request, decision: "allow", sessionId: " chat ")
        XCTAssertEqual(model.approvalDecisionsInFlight[request], "allow")
        XCTAssertEqual(model.approvalDecisionSessionScope[request], "chat")
        model.clearDecisionInFlight(request)
        XCTAssertNil(model.approvalDecisionsInFlight[request])
    }
}

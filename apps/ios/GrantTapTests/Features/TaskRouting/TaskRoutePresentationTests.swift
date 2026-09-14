import XCTest
@testable import GrantTap

final class TaskRoutePresentationTests: XCTestCase {
    private func sending(id: String = "d-1") -> OutgoingDelivery {
        let now = Date().timeIntervalSince1970 * 1_000
        return OutgoingDelivery(
            id: id, text: "hi", agent: nil, cwd: nil, sessionId: "s-1",
            requestId: nil, roomId: "room-a", attachments: [],
            preferredMcp: nil, skill: nil,
            createdAt: now, updatedAt: now, attempts: 1,
            state: .sending, error: nil, nextRetryAt: nil
        )
    }

    func testABusyChatSaysSoInsteadOfBlamingTheComputer() {
        let status = TaskRoutePresentation.deliveryStatus(
            sending(), route: nil, chatIsBusy: true
        )
        XCTAssertTrue(status.lowercased().contains("busy"))
        XCTAssertFalse(
            status.lowercased().contains("mac"),
            "the computer is fine; pointing at it would be misleading"
        )
    }

    func testAFreeChatKeepsTheOrdinaryWording() {
        let status = TaskRoutePresentation.deliveryStatus(
            sending(), route: nil, chatIsBusy: false
        )
        XCTAssertTrue(status.contains("waiting"))
    }

    func testOfflineComputerOverridesStaleProviderWorkingState() {
        let offline = ChatComputerRoute(
            roomId: "room-a",
            computerName: "Studio PC",
            phase: .macOffline
        )
        let live = ChatComputerRoute(
            roomId: "room-a",
            computerName: "Studio PC",
            phase: .live
        )

        XCTAssertEqual(
            TaskRoutePresentation.presence(nativeState: "working", route: offline),
            .offline
        )
        XCTAssertEqual(
            TaskRoutePresentation.presence(nativeState: "working", route: live),
            .working
        )
    }

    func testOfflineDeliveryNamesItsPinnedComputerAndStaysQueued() {
        let route = ChatComputerRoute(
            roomId: "room-a",
            computerName: "A very long workstation name",
            phase: .phoneOffline
        )
        var delivery = deliveryFixture()
        delivery.state = .queued

        XCTAssertEqual(
            TaskRoutePresentation.deliveryStatus(delivery, route: route),
            "Queued until A very long workstation name reconnects"
        )
    }

    func testUnsupportedProviderNoLongerHardBlocksCursorComposer() throws {
        let route = ChatComputerRoute(
            roomId: "room-a", computerName: "Studio PC", phase: .live
        )

        XCTAssertNil(TaskRoutePresentation.providerUnavailableReason("cursor"))
        XCTAssertNil(TaskRoutePresentation.sendAvailability(agent: "cursor", route: route))
    }

    func testOfflineComputerKeepsSupportedProviderMessageQueuedWithItsName() throws {
        let route = ChatComputerRoute(
            roomId: "room-a", computerName: "Studio PC", phase: .macOffline
        )

        let availability = try XCTUnwrap(
            TaskRoutePresentation.sendAvailability(agent: "grok", route: route)
        )

        XCTAssertFalse(availability.blocksSending)
        XCTAssertEqual(
            availability.message,
            "Studio PC is offline. Your message will stay queued until it reconnects."
        )
    }

    func testMissingComputerBlocksSendInsteadOfPretendingThePhoneCanRunIt() throws {
        let availability = try XCTUnwrap(
            TaskRoutePresentation.sendAvailability(agent: "codex", route: nil)
        )

        XCTAssertTrue(availability.blocksSending)
        XCTAssertEqual(
            availability.message,
            "No computer is selected. Link or select a Mac/PC before sending."
        )
    }

    @MainActor
    func testOfflineSendWaitsWithoutConsumingAnAttempt() throws {
        let model = AppModel()
        let pairing = Pairing(
            relayUrl: "ws://127.0.0.1:1", room: "room-a", role: "phone",
            deviceName: "Studio PC", senderId: "sender",
            myPublicKey: "public", mySecretKey: "secret", peerPublicKey: "peer"
        )
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: pairing, prefer: true
        )
        model.roomRuntime["room-a"] = AppModel.RoomRuntime(socketUp: false, socketUpSince: 0)
        model.deliveries = []

        model.sendMessage("queued hello", agent: "grok", roomId: "room-a")

        let delivery = try XCTUnwrap(model.deliveries.first)
        XCTAssertEqual(delivery.roomId, "room-a")
        XCTAssertEqual(delivery.state, .queued)
        XCTAssertEqual(delivery.attempts, 0)
    }

    func testOfflineQueueRetriesOldestMessageFirst() {
        var older = deliveryFixture()
        older = OutgoingDelivery(
            id: "older", text: older.text, agent: older.agent, cwd: older.cwd,
            sessionId: older.sessionId, requestId: older.requestId, roomId: older.roomId,
            attachments: [], preferredMcp: nil, skill: nil,
            createdAt: 1, updatedAt: 1, attempts: 0, state: .queued,
            error: nil, nextRetryAt: nil
        )
        var newer = deliveryFixture()
        newer = OutgoingDelivery(
            id: "newer", text: newer.text, agent: newer.agent, cwd: newer.cwd,
            sessionId: newer.sessionId, requestId: newer.requestId, roomId: newer.roomId,
            attachments: [], preferredMcp: nil, skill: nil,
            createdAt: 2, updatedAt: 2, attempts: 0, state: .queued,
            error: nil, nextRetryAt: nil
        )

        XCTAssertEqual(
            TaskDeliveryQueue.oldestFirst([newer, older]).map(\.id),
            ["older", "newer"]
        )
    }

    func testNeverAttemptedOfflineMessageUsesDurableQueueWindow() {
        var delivery = deliveryFixture()
        delivery.state = .queued
        delivery.attempts = 0

        XCTAssertEqual(
            TaskDeliveryQueue.retentionMilliseconds(for: delivery),
            24 * 60 * 60 * 1_000
        )
    }

    @MainActor
    func testNewTaskStubWaitsUntilTheComputerConfirmsProviderWork() throws {
        let model = AppModel()
        model.sessions = []

        let stubId = model.ensureLocalSession(
            sessionId: nil, agent: "grok", cwd: nil,
            title: "hello", at: 1
        )

        XCTAssertEqual(
            try XCTUnwrap(model.sessions.first { $0.sessionId == stubId }).state,
            "waiting"
        )
    }

    private func deliveryFixture() -> OutgoingDelivery {
        OutgoingDelivery(
            id: "delivery", text: "hello", agent: "grok", cwd: nil,
            sessionId: "session", requestId: nil, roomId: "room-a",
            attachments: [], preferredMcp: nil, skill: nil,
            createdAt: 1, updatedAt: 1, attempts: 0, state: .queued,
            error: nil, nextRetryAt: nil
        )
    }
}

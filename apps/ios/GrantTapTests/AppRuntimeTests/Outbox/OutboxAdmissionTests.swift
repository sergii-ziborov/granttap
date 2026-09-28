import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    func testThirtyThirdActiveDeliveryIsVisibleFailureWithoutEvictingPendingRows() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let active = (0..<32).map { index in
            existingSessionDelivery(
                createdAt: now - Double(index),
                id: "active-\(index)",
                text: "pending \(index)"
            )
        }
        var terminal = existingSessionDelivery(
            createdAt: now - 60_000,
            id: "replaceable-terminal",
            text: "old failure"
        )
        terminal.state = .failed
        terminal.error = "already terminal"
        let newest = existingSessionDelivery(
            createdAt: now + 1,
            id: "active-32",
            text: "must be rejected visibly"
        )

        let result = DeliveryPersistence.admit(newest, into: active + [terminal])

        XCTAssertFalse(result.shouldSend)
        let preserved = result.deliveries.filter { $0.id.hasPrefix("active-") && $0.id != newest.id }
        XCTAssertEqual(try deterministicJSON(preserved), try deterministicJSON(active))
        XCTAssertFalse(result.deliveries.contains { $0.id == terminal.id })
        let rejection = try XCTUnwrap(result.deliveries.first { $0.id == newest.id })
        XCTAssertEqual(rejection.state, .failed)
        XCTAssertEqual(rejection.admissionRejected, true)
        XCTAssertTrue(rejection.attachments.isEmpty)
        XCTAssertNotNil(rejection.error)
        XCTAssertEqual(result.deliveries.count, 33)
        let persisted = try XCTUnwrap(DeliveryPersistence.encodedData(result.deliveries))
        XCTAssertLessThanOrEqual(persisted.count, DeliveryPersistence.maxPersistedBytes)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("granttap-outbox-admission-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("outgoing-deliveries.json")
        defer { try? FileManager.default.removeItem(at: root) }
        DeliveryPersistence.save(result.deliveries, to: file)
        let reloaded = DeliveryPersistence.load(from: file)
        XCTAssertEqual(reloaded.count, 33)
        XCTAssertEqual(reloaded.first { $0.id == newest.id }?.admissionRejected, true)
    }

    @MainActor
    func testSendMessageRejectsThirtyThirdActiveRowWithoutBubbleOrAttempt() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let active = (0..<32).map { index in
            existingSessionDelivery(
                createdAt: now - Double(index),
                id: "send-active-\(index)",
                text: "pending \(index)"
            )
        }
        let activeIDs = Set(active.map(\.id))
        let model = AppModel()
        model.deliveries = active

        model.sendMessage("visible admission failure", sessionId: "existing-session")

        let preserved = model.deliveries.filter { activeIDs.contains($0.id) }
        XCTAssertEqual(try deterministicJSON(preserved), try deterministicJSON(active))
        let rejection = try XCTUnwrap(model.deliveries.first { !activeIDs.contains($0.id) })
        XCTAssertEqual(rejection.state, .failed)
        XCTAssertEqual(rejection.admissionRejected, true)
        XCTAssertEqual(rejection.attempts, 0)
        XCTAssertTrue(
            model.deliveries(for: "existing-session").contains { $0.id == rejection.id }
        )
        XCTAssertFalse(
            (model.activities["existing-session"]?.entries ?? []).contains {
                $0.id == "local-user-\(rejection.id)"
            }
        )
    }

    func testOversizedNewestDeliveryBecomesCompactFailureAndPreservesActiveRows() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let active = existingSessionDelivery(
            createdAt: now,
            id: "existing-active",
            text: "keep me"
        )
        var newest = existingSessionDelivery(
            createdAt: now + 1,
            id: "oversized-newest",
            text: "quoted \"text\" with \\ escapes and emoji 📦"
        )
        newest.attachments = [UserAttachment(
            name: "large.json",
            mimeType: "application/json",
            data: String(repeating: "x", count: 20_000)
        )]

        let result = DeliveryPersistence.admit(
            newest,
            into: [active],
            maxActiveCount: 32,
            maxActiveEncodedBytes: 1_000,
            maxPersistedBytes: 4_000
        )

        XCTAssertFalse(result.shouldSend)
        XCTAssertEqual(result.deliveries.filter { $0.state == .sending }.map(\.id), [active.id])
        let rejection = try XCTUnwrap(result.deliveries.first { $0.id == newest.id })
        XCTAssertEqual(rejection.state, .failed)
        XCTAssertEqual(rejection.admissionRejected, true)
        XCTAssertTrue(rejection.attachments.isEmpty)
        let persisted = try XCTUnwrap(DeliveryPersistence.encodedData(result.deliveries))
        XCTAssertLessThanOrEqual(persisted.count, 4_000)
    }

    func testAdmissionFailureBoundsHostileIdentifiersWithinReservedBytes() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let active = existingSessionDelivery(
            createdAt: now,
            id: "existing-active",
            text: "must remain byte-identical"
        )
        let hostile = String(repeating: "\"\\", count: 10_000)
        var newest = existingSessionDelivery(
            createdAt: now + 1,
            id: hostile,
            text: hostile,
            sessionId: hostile,
            requestId: hostile
        )
        newest.roomId = hostile

        let result = DeliveryPersistence.admit(
            newest,
            into: [active],
            maxActiveCount: 1,
            maxActiveEncodedBytes: 1_000,
            maxPersistedBytes: 4_000
        )

        XCTAssertFalse(result.shouldSend)
        XCTAssertEqual(
            try deterministicJSON(result.deliveries.filter { $0.id == active.id }),
            try deterministicJSON([active])
        )
        let rejection = try XCTUnwrap(result.deliveries.first { $0.admissionRejected == true })
        XCTAssertLessThan(rejection.id.utf8.count, newest.id.utf8.count)
        XCTAssertLessThan(rejection.sessionId?.utf8.count ?? 0, newest.sessionId?.utf8.count ?? 0)
        XCTAssertLessThan(rejection.requestId?.utf8.count ?? 0, newest.requestId?.utf8.count ?? 0)
        let persisted = try XCTUnwrap(DeliveryPersistence.encodedData(result.deliveries))
        XCTAssertLessThanOrEqual(persisted.count, 4_000)
    }

    @MainActor
    func testAdmissionFailureCannotBeRetriedManuallyOrByReconnect() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let newest = existingSessionDelivery(
            createdAt: now,
            id: "non-retryable-admission",
            text: String(repeating: "x", count: 10_000)
        )
        let admission = DeliveryPersistence.admit(
            newest,
            into: [],
            maxActiveCount: 1,
            maxActiveEncodedBytes: 500,
            maxPersistedBytes: 4_000
        )
        XCTAssertFalse(admission.shouldSend)
        let model = AppModel()
        model.deliveries = admission.deliveries
        let before = try deterministicJSON(model.deliveries)

        model.retryDelivery(newest.id)
        model.attemptDelivery(newest.id)
        model.retryQueuedDeliveries()

        XCTAssertEqual(try deterministicJSON(model.deliveries), before)
        XCTAssertEqual(model.deliveries.first?.state, .failed)
        XCTAssertEqual(model.deliveries.first?.admissionRejected, true)
    }

    @MainActor
    func testAdmissionFailureRemainsNonRetryableAfterSessionRemap() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let newest = existingSessionDelivery(
            createdAt: now,
            id: "remapped-admission",
            text: String(repeating: "x", count: 10_000),
            sessionId: "phone-stub"
        )
        let admission = DeliveryPersistence.admit(
            newest,
            into: [],
            maxActiveCount: 1,
            maxActiveEncodedBytes: 500,
            maxPersistedBytes: 4_000
        )
        let model = AppModel()
        model.localOnlySessionIds = ["phone-stub"]
        model.deliveries = admission.deliveries

        model.remapLocalSession(from: "phone-stub", to: "machine-session")

        XCTAssertEqual(model.deliveries.first?.sessionId, "machine-session")
        XCTAssertEqual(model.deliveries.first?.admissionRejected, true)
        let beforeRetry = try deterministicJSON(model.deliveries)
        model.retryDelivery(newest.id)
        model.attemptDelivery(newest.id)
        model.retryQueuedDeliveries()
        XCTAssertEqual(try deterministicJSON(model.deliveries), beforeRetry)
    }

    func testAdmissionUsesExactJSONEncodedBytesIncludingEscapesAndMetadata() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let row = existingSessionDelivery(
            createdAt: now,
            id: "encoded-byte-row",
            text: String(repeating: "\"\\\n", count: 40) + "💾"
        )
        let exactBytes = try JSONEncoder().encode([row]).count

        let exactFit = DeliveryPersistence.admit(
            row,
            into: [],
            maxActiveCount: 1,
            maxActiveEncodedBytes: exactBytes,
            maxPersistedBytes: exactBytes + 1_000
        )
        XCTAssertTrue(exactFit.shouldSend)
        XCTAssertEqual(exactFit.deliveries.map(\.id), [row.id])

        let oneByteShort = DeliveryPersistence.admit(
            row,
            into: [],
            maxActiveCount: 1,
            maxActiveEncodedBytes: exactBytes - 1,
            maxPersistedBytes: exactBytes + 1_000
        )
        XCTAssertFalse(oneByteShort.shouldSend)
        XCTAssertEqual(oneByteShort.deliveries.first?.state, .failed)
    }

}

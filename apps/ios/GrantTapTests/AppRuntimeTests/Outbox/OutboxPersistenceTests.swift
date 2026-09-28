import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    func testDeliveryLoadRejectsOversizedFileBeforeDecode() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("granttap-outbox-load-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("outgoing-deliveries.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let row = existingSessionDelivery(createdAt: 1, id: "bounded-load", text: "small")
        let encoded = try JSONEncoder().encode([row])
        var oversized = encoded
        oversized.append(contentsOf: [0x20, 0x20])
        try oversized.write(to: file)

        XCTAssertTrue(
            DeliveryPersistence.load(from: file, maxEncodedBytes: encoded.count).isEmpty
        )
        try encoded.write(to: file)
        XCTAssertEqual(
            DeliveryPersistence.load(from: file, maxEncodedBytes: encoded.count).map(\.id),
            [row.id]
        )
    }

    func testDeliveryLoadPreservesLegacyActiveRowsAboveCurrentCountCap() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("granttap-outbox-legacy-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("outgoing-deliveries.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let active = (0..<34).map { index in
            existingSessionDelivery(
                createdAt: Double(34 - index),
                id: "legacy-active-\(index)",
                text: "pending \(index)"
            )
        }
        let encoded = try XCTUnwrap(DeliveryPersistence.encodedData(active))
        try encoded.write(to: file)

        let loaded = DeliveryPersistence.load(from: file, maxEncodedBytes: encoded.count)

        XCTAssertEqual(loaded.map(\.id), active.map(\.id))
    }

    func testLegacyOverCapStateTransitionPersistsWithoutResurrectingActiveRow() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("granttap-outbox-migration-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("outgoing-deliveries.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let active = (0..<34).map { index in
            existingSessionDelivery(
                createdAt: Double(34 - index),
                id: "migrating-active-\(index)",
                text: "pending \(index)"
            )
        }
        try XCTUnwrap(DeliveryPersistence.encodedData(active)).write(to: file)
        var transitioning = DeliveryPersistence.load(from: file)
        XCTAssertEqual(transitioning.count, 34)
        transitioning[0].state = .failed
        transitioning[0].error = "terminal failure"
        transitioning[0].updatedAt += 1
        let overflowTerminalIDs = (0..<5).map { "legacy-terminal-\($0)" }
        transitioning.append(contentsOf: overflowTerminalIDs.map { id in
            var terminal = existingSessionDelivery(
                createdAt: 0,
                id: id,
                text: "old terminal"
            )
            terminal.state = .failed
            terminal.error = "old terminal"
            return terminal
        })

        DeliveryPersistence.save(transitioning, to: file)
        let reloaded = DeliveryPersistence.load(from: file)

        XCTAssertEqual(reloaded.count, 34)
        XCTAssertEqual(reloaded.filter { $0.state == .sending }.count, 33)
        XCTAssertEqual(
            reloaded.first { $0.id == transitioning[0].id }?.state,
            .failed
        )
        XCTAssertTrue(reloaded.allSatisfy { !overflowTerminalIDs.contains($0.id) })
    }

    @MainActor
    func testLegacyOverCapPruneKeepsNewlyFailedRowBesideEveryRemainingActiveRow() {
        let now = Date().timeIntervalSince1970 * 1000
        var active = (0..<34).map { index in
            existingSessionDelivery(
                createdAt: index == 0 ? now - 700_000 : now - Double(index),
                id: "prune-legacy-active-\(index)",
                text: "pending \(index)"
            )
        }
        active[0].updatedAt = now - 700_000
        active[0].processingAcknowledgedAt = now - 700_000
        let expiredId = active[0].id
        let model = AppModel()
        model.deliveries = active

        model.pruneStaleDeliveries()

        XCTAssertEqual(model.deliveries.count, 34)
        XCTAssertEqual(model.deliveries.filter { $0.state == .sending }.count, 33)
        XCTAssertEqual(model.deliveries.first { $0.id == expiredId }?.state, .failed)
        XCTAssertNotNil(model.deliveries.first { $0.id == expiredId }?.error)
    }

}

import XCTest
import TweetNacl
@testable import GrantTap

final class AccountSpaceSyncBoundaryTests: XCTestCase {
    @MainActor
    func testInitialHandshakeGetsTimeToRecoverTheSavedRouteBeforeAccountRekey() async throws {
        let previous = PairedConnectionStore.load()
        defer { _ = PairedConnectionStore.save(previous) }
        let model = AppModel()
        let phone = try NaclBox.keyPair(), mac = try NaclBox.keyPair()
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:9",
            room: String(repeating: "b", count: 32), role: "phone",
            deviceName: "Test Mac", senderId: "test-phone",
            myPublicKey: phone.publicKey.base64EncodedString(),
            mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: mac.publicKey.base64EncodedString())
        let session = GrantTapAccountSession(accountId: "owner", token: "test-token")
        let computer = machine()
        let now = Date().timeIntervalSince1970 * 1_000
        var registry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing, now: now - 600_000)
        registry = ConnectionRegistryLogic.noteAccountRecovery(registry,
            roomId: pairing.room, peerPublicKey: pairing.peerPublicKey,
            reference: .init(accountId: session.accountId, machineId: computer.id), nowMs: now - 600_000)
        XCTAssertTrue(PairedConnectionStore.save(registry))
        model.connectionRegistry = registry
        let relay = RelayClient(pairing: pairing)
        model.relaysByRoom[pairing.room] = relay
        relay.wantsConnection = true
        relay.initialConnectionStartedAt = Date().timeIntervalSince1970
        defer { relay.disconnect() }
        var recoveryRequests = 0
        try await model.synchronizeAccountSpace(session, loadComputers: { _ in [computer] },
            recover: { _, _ in recoveryRequests += 1; return [] },
            currentAccountId: { session.accountId })
        XCTAssertEqual(recoveryRequests, 0)
        XCTAssertEqual(PairedConnectionStore.load(), registry)
        relay.initialConnectionStartedAt = Date().timeIntervalSince1970 - 31
        do {
            try await model.synchronizeAccountSpace(session, loadComputers: { _ in [computer] },
                recover: { _, _ in recoveryRequests += 1; return [] },
                currentAccountId: { session.accountId })
            XCTFail("A failed initial handshake must eventually allow recovery")
        } catch AccountBridgeError.recoveryFailed { }
        XCTAssertEqual(recoveryRequests, 1)
        relay.initialConnectionStartedAt = Date().timeIntervalSince1970
        do {
            try await model.synchronizeAccountSpace(session, repairRoomId: pairing.room,
                loadComputers: { _ in [computer] },
                recover: { _, _ in recoveryRequests += 1; return [] },
                currentAccountId: { session.accountId })
            XCTFail("Explicit repair must bypass the initial handshake window")
        } catch AccountBridgeError.recoveryFailed { }
        XCTAssertEqual(recoveryRequests, 2)
        relay.initialConnectionStartedAt = nil
        XCTAssertFalse(relay.awaitingInitialPeer())
        relay.initialConnectionStartedAt = Date().timeIntervalSince1970 + 1
        XCTAssertFalse(relay.awaitingInitialPeer())
        relay.wantsConnection = false
        XCTAssertFalse(relay.awaitingInitialPeer())
    }

    private func machine() -> AccountComputer {
        AccountComputer(id: UUID().uuidString.lowercased(), name: "Mac",
                        createdAt: 1, lastSeenAt: Date().timeIntervalSince1970 * 1_000)
    }

    @MainActor
    func testAuthenticatedLiveComputerKeepsItsPhoneKeyWhileCatalogIsDelayed() async throws {
        let previous = PairedConnectionStore.load()
        defer { _ = PairedConnectionStore.save(previous) }
        let model = AppModel()
        let phone = try NaclBox.keyPair(), mac = try NaclBox.keyPair()
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:9",
            room: String(repeating: "a", count: 32), role: "phone",
            deviceName: "Test Mac", senderId: "test-phone",
            myPublicKey: phone.publicKey.base64EncodedString(),
            mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: mac.publicKey.base64EncodedString())
        let session = GrantTapAccountSession(accountId: "owner", token: "test-token")
        let computer = machine()
        let now = Date().timeIntervalSince1970 * 1_000
        var registry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing, now: now - 600_000)
        registry = ConnectionRegistryLogic.noteAccountRecovery(registry,
            roomId: pairing.room, peerPublicKey: pairing.peerPublicKey,
            reference: .init(accountId: session.accountId, machineId: computer.id), nowMs: now - 600_000)
        registry = ConnectionRegistryLogic.noteCatalog(registry,
            roomId: pairing.room, generatedAt: now - 600_000, machineName: computer.name)
        XCTAssertTrue(PairedConnectionStore.save(registry))
        model.connectionRegistry = registry
        model.roomRuntime = [pairing.room: .init(socketUp: true, lastHeartbeatAt: now)]
        var recoveryRequests = 0
        do {
            try await model.synchronizeAccountSpace(session, loadComputers: { _ in [computer] },
                recover: { _, _ in recoveryRequests += 1; return [] },
                currentAccountId: { session.accountId })
        } catch { XCTFail("A delayed catalog must not invalidate an authenticated live route: \(error)") }
        XCTAssertEqual(recoveryRequests, 0)
        XCTAssertEqual(model.connectionRegistry, registry)
        XCTAssertEqual(PairedConnectionStore.load(), registry)
    }

    @MainActor
    func testAccountChangeBeforeRecoveryCancelsWithoutSavingAComputer() async {
        let model = AppModel()
        model.connectionRegistry = .empty
        let session = GrantTapAccountSession(accountId: "original", token: "test-token")
        do {
            try await model.synchronizeAccountSpace(session,
                loadComputers: { _ in [self.machine()] },
                recover: { _, _ in XCTFail("Recovery must not start for another account"); return [] },
                currentAccountId: { "different" })
            XCTFail("Changing account must cancel the old recovery")
        } catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(model.connectionRegistry.connections.isEmpty)
    }

    @MainActor
    func testAccountChangeDuringRecoveryCannotSaveTheOfferedKey() async {
        let model = AppModel()
        model.connectionRegistry = .empty
        let session = GrantTapAccountSession(accountId: "original", token: "test-token")
        let offered = machine()
        var accountChecks = 0
        do {
            try await model.synchronizeAccountSpace(session,
                loadComputers: { _ in [offered] },
                recover: { _, _ in
                    [RecoveredAccountConnection(machineId: offered.id,
                        pairing: PairingFixture.pairing(room: String(repeating: "c", count: 32)))]
                }, currentAccountId: {
                    accountChecks += 1
                    return accountChecks == 1 ? session.accountId : "different"
                })
            XCTFail("A stale passkey must not save a new pairing")
        } catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(model.connectionRegistry.connections.isEmpty)
        XCTAssertEqual(accountChecks, 2)
    }

    @MainActor
    func testInvalidRecoveredPairingIsRejectedBeforeKeychainWrite() async {
        let model = AppModel()
        model.connectionRegistry = .empty
        let session = GrantTapAccountSession(accountId: "original", token: "test-token")
        let offered = machine()
        var invalid = PairingFixture.pairing(room: String(repeating: "d", count: 32))
        invalid.role = "machine"
        do {
            try await model.synchronizeAccountSpace(session,
                loadComputers: { _ in [offered] },
                recover: { _, _ in
                    [RecoveredAccountConnection(machineId: offered.id, pairing: invalid)]
                }, currentAccountId: { session.accountId })
            XCTFail("Invalid encrypted pairing must be rejected")
        } catch AccountBridgeError.storage { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(model.connectionRegistry.connections.isEmpty)
    }

    @MainActor
    func testUnavailableFirstBatchDoesNotHideLaterAccountComputers() async throws {
        let previous = PairedConnectionStore.load()
        let phone = try NaclBox.keyPair(), mac = try NaclBox.keyPair()
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:9",
                              room: String(repeating: "e", count: 32), role: "phone",
                              deviceName: "Test Mac", senderId: "test-phone",
                              myPublicKey: phone.publicKey.base64EncodedString(),
                              mySecretKey: phone.secretKey.base64EncodedString(),
                              peerPublicKey: mac.publicKey.base64EncodedString())
        let model = AppModel()
        defer {
            model.relaysByRoom.values.forEach { $0.disconnect() }
            _ = PairedConnectionStore.save(previous)
        }
        model.connectionRegistry = .empty
        let session = GrantTapAccountSession(accountId: "account", token: "test-token")
        let now = Date().timeIntervalSince1970 * 1_000
        let computers = (0..<9).map { index in
            AccountComputer(id: UUID().uuidString.lowercased(), name: "Mac", createdAt: 1,
                            lastSeenAt: now - (index == 8 ? 1_000 : 0))
        }
        let ninth = computers[8]
        do {
            try await model.synchronizeAccountSpace(session,
                loadComputers: { _ in computers },
                recover: { batch, _ in
                    guard batch.contains(where: { $0.id == ninth.id }) else { return [] }
                    return [RecoveredAccountConnection(machineId: ninth.id,
                        pairing: pairing)]
                }, currentAccountId: { session.accountId })
            XCTFail("Unavailable computers should remain visible as a recovery failure")
        } catch AccountBridgeError.recoveryFailed { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(model.connectionRegistry.connections.first?.linkedMachineId, ninth.id)
    }
}

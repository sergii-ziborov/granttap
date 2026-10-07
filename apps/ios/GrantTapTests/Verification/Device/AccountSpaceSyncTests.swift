import XCTest
import TweetNacl
@testable import GrantTap

final class AccountSpaceSyncTests: XCTestCase {
    @MainActor
    func testOnlineComputerWithoutRecoveredRouteReportsFailure() async throws {
        let model = AppModel()
        model.connectionRegistry = .empty
        let session = GrantTapAccountSession(accountId: "current", token: "session")
        let machine = AccountComputer(id: UUID().uuidString.lowercased(), name: "Mac",
                                      createdAt: 1, lastSeenAt: Date().timeIntervalSince1970 * 1_000)
        do {
            try await model.synchronizeAccountSpace(session, loadComputers: { _ in [machine] },
                recover: { _, _ in [] }, currentAccountId: { session.accountId })
            XCTFail("An offered computer without a usable encrypted route needs a retry")
        } catch AccountBridgeError.unavailable { }
    }

    @MainActor
    func testOldQRAccountDoesNotBlockRecoveryOfCurrentAccount() async throws {
        let previous = PairedConnectionStore.load()
        let phone = try NaclBox.keyPair(), mac = try NaclBox.keyPair()
        func makePairing(_ letter: String) -> Pairing {
            Pairing(relayUrl: "ws://127.0.0.1:9", room: String(repeating: letter, count: 32),
                    role: "phone", deviceName: "Test Mac", senderId: "test-phone",
                    myPublicKey: phone.publicKey.base64EncodedString(),
                    mySecretKey: phone.secretKey.base64EncodedString(),
                    peerPublicKey: mac.publicKey.base64EncodedString())
        }
        let old = makePairing("a"), fresh = makePairing("b")
        let model = AppModel()
        defer {
            model.relaysByRoom.values.forEach { $0.disconnect() }
            _ = PairedConnectionStore.save(previous)
        }
        let credential = AccountMachineCredential(accountId: "old", machineId: "old-mac",
                                                  machineToken: String(repeating: "t", count: 43))
        model.connectionRegistry = ConnectionRegistryLogic.noteAccountLink(
            ConnectionRegistryLogic.upsert(.empty, pairing: old), roomId: old.room,
            peerPublicKey: old.peerPublicKey, credential: credential)
        let session = GrantTapAccountSession(accountId: "current", token: "session")
        let machine = AccountComputer(id: UUID().uuidString.lowercased(), name: "Mac",
                                      createdAt: 1, lastSeenAt: Date().timeIntervalSince1970 * 1_000)
        try await model.synchronizeAccountSpace(session, loadComputers: { _ in [machine] },
            recover: { _, _ in [RecoveredAccountConnection(machineId: machine.id, pairing: fresh)] },
            currentAccountId: { session.accountId })
        XCTAssertEqual(model.connectionRegistry.connections.count, 2)
        XCTAssertEqual(model.connectionRegistry.connections.first(where: { $0.id == fresh.room })?
                           .linkedMachineId, machine.id)
    }

    func testPasskeyRecoveryReplacesOldQRMachineCredentialForSameRoom() {
        let pairing = PairingFixture.pairing(room: String(repeating: "c", count: 32))
        let stale = AccountMachineCredential(accountId: "account", machineId: "old-machine",
                                             machineToken: String(repeating: "t", count: 43))
        let qr = ConnectionRegistryLogic.noteAccountLink(
            ConnectionRegistryLogic.upsert(.empty, pairing: pairing), roomId: pairing.room,
            peerPublicKey: pairing.peerPublicKey, credential: stale)
        let recovered = ConnectionRegistryLogic.noteAccountRecovery(
            qr, roomId: pairing.room, peerPublicKey: pairing.peerPublicKey,
            reference: AccountMachineReference(accountId: "account", machineId: "mac-machine"))
        XCTAssertNil(recovered.connections.first?.accountCredential)
        XCTAssertEqual(recovered.connections.first?.linkedMachineId, "mac-machine")
    }

    @MainActor
    func testOldQRRoomIsRecoveredIntoTheSameMacAccountOnce() async throws {
        let now = Date().timeIntervalSince1970 * 1_000
        let phone = try NaclBox.keyPair(), mac = try NaclBox.keyPair()
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:9", room: String(repeating: "b", count: 32),
                              role: "phone", deviceName: "Mac", senderId: "test-phone",
                              myPublicKey: phone.publicKey.base64EncodedString(),
                              mySecretKey: phone.secretKey.base64EncodedString(),
                              peerPublicKey: mac.publicKey.base64EncodedString())
        let credential = AccountMachineCredential(accountId: "account", machineId: "mac",
                                                  machineToken: String(repeating: "t", count: 43))
        var linked = ConnectionRegistryLogic.noteAccountLink(
            ConnectionRegistryLogic.upsert(.empty, pairing: pairing, now: now - 600_000),
            roomId: pairing.room, peerPublicKey: pairing.peerPublicKey, credential: credential)
        XCTAssertEqual(AccountSpaceSync.staleQRRoomToRecover(linked, accountId: "account", nowMs: now),
                       pairing.room)
        XCTAssertNil(AccountSpaceSync.staleQRRoomToRecover(linked, accountId: "another", nowMs: now))

        linked = ConnectionRegistryLogic.noteAccountRecovery(
            linked, roomId: pairing.room, peerPublicKey: pairing.peerPublicKey,
            reference: AccountMachineReference(accountId: "account", machineId: "mac"), nowMs: now)
        XCTAssertEqual(linked.connections.count, 1)
        XCTAssertNil(linked.connections.first?.accountCredential)
        XCTAssertNil(AccountSpaceSync.staleQRRoomToRecover(linked, accountId: "account", nowMs: now + 119_000))
        XCTAssertEqual(AccountSpaceSync.staleQRRoomToRecover(linked, accountId: "account", nowMs: now + 121_000), pairing.room)

        let previous = PairedConnectionStore.load()
        let model = AppModel()
        model.connectionRegistry = ConnectionRegistryLogic.noteAccountLink(
            ConnectionRegistryLogic.upsert(.empty, pairing: pairing, now: now - 600_000),
            roomId: pairing.room, peerPublicKey: pairing.peerPublicKey, credential: credential)
        defer {
            model.relaysByRoom.values.forEach { $0.disconnect() }
            _ = PairedConnectionStore.save(previous)
        }
        let key = try NaclBox.keyPair()
        var renewed = pairing
        renewed.myPublicKey = key.publicKey.base64EncodedString()
        renewed.mySecretKey = key.secretKey.base64EncodedString()
        let session = GrantTapAccountSession(accountId: "account", token: "session")
        let machine = AccountComputer(id: "mac", name: "Mac", createdAt: 1, lastSeenAt: now)
        try await model.synchronizeAccountSpace(session, loadComputers: { _ in [machine] },
            recover: { targets, _ in
                XCTAssertEqual(targets.map(\.id), ["mac"])
                return [RecoveredAccountConnection(machineId: "mac", pairing: renewed)]
            }, currentAccountId: { "account" })
        XCTAssertEqual(model.connectionRegistry.connections.count, 1)
        XCTAssertEqual(model.connectionRegistry.preferredId, pairing.room)
        XCTAssertEqual(model.connectionRegistry.preferred?.pairing.myPublicKey, renewed.myPublicKey)
        XCTAssertNil(model.connectionRegistry.preferred?.accountCredential)
    }

    func testFreshQRRoomDoesNotTriggerUnnecessaryPasskeyRecovery() {
        let now = Date().timeIntervalSince1970 * 1_000
        let pairing = PairingFixture.pairing(room: String(repeating: "b", count: 32))
        let credential = AccountMachineCredential(accountId: "account", machineId: "mac",
                                                  machineToken: String(repeating: "t", count: 43))
        let fresh = ConnectionRegistryLogic.noteAccountLink(
            ConnectionRegistryLogic.upsert(.empty, pairing: pairing, now: now - 30_000),
            roomId: pairing.room, peerPublicKey: pairing.peerPublicKey, credential: credential)
        XCTAssertNil(AccountSpaceSync.staleQRRoomToRecover(fresh, accountId: "account", nowMs: now))
        let reported = ConnectionRegistryLogic.noteCatalog(fresh, roomId: pairing.room,
                                                            generatedAt: now - 30_000, machineName: "Mac")
        XCTAssertNil(AccountSpaceSync.staleQRRoomToRecover(reported, accountId: "account", nowMs: now))
    }

    @MainActor
    func testOfflineRecoveredRoomAutomaticallyRequestsFreshPasskeyOffer() async throws {
        let previous = PairedConnectionStore.load()
        let firstPhone = try NaclBox.keyPair(), secondPhone = try NaclBox.keyPair()
        let mac = try NaclBox.keyPair()
        let room = String(repeating: "f", count: 32)
        func makePairing(publicKey: Data, secretKey: Data) -> Pairing {
            Pairing(relayUrl: "ws://127.0.0.1:9", room: room, role: "phone",
                    deviceName: "Mac", senderId: "phone",
                    myPublicKey: publicKey.base64EncodedString(),
                    mySecretKey: secretKey.base64EncodedString(),
                    peerPublicKey: mac.publicKey.base64EncodedString())
        }
        let old = makePairing(publicKey: firstPhone.publicKey, secretKey: firstPhone.secretKey)
        let fresh = makePairing(publicKey: secondPhone.publicKey, secretKey: secondPhone.secretKey)
        let account = "owner", machineId = UUID().uuidString.lowercased()
        let model = AppModel()
        defer {
            model.relaysByRoom.values.forEach { $0.disconnect() }
            _ = PairedConnectionStore.save(previous)
        }
        model.connectionRegistry = ConnectionRegistryLogic.noteAccountRecovery(
            ConnectionRegistryLogic.upsert(.empty, pairing: old, now: 1), roomId: room,
            peerPublicKey: old.peerPublicKey,
            reference: AccountMachineReference(accountId: account, machineId: machineId), nowMs: 1)
        let session = GrantTapAccountSession(accountId: account, token: "session")
        let machine = AccountComputer(id: machineId, name: "Mac", createdAt: 1,
                                      lastSeenAt: Date().timeIntervalSince1970 * 1_000)
        try await model.synchronizeAccountSpace(session,
            loadComputers: { _ in [machine] },
            recover: { targets, _ in
                XCTAssertEqual(targets.map(\.id), [machineId])
                return [RecoveredAccountConnection(machineId: machineId, pairing: fresh)]
            }, currentAccountId: { account })
        XCTAssertEqual(model.connectionRegistry.connections.first?.pairing.myPublicKey,
                       fresh.myPublicKey)
        XCTAssertEqual(model.connectionRegistry.connections.first?.linkedMachineId, machineId)
    }

    func testRecoveryKeepsSuccessfulMachinesWhenAnotherIsUnavailable() async {
        let machines = ["a", "b", "c"].map { id in
            AccountComputer(id: String(repeating: id, count: 32), name: id,
                            createdAt: 1, lastSeenAt: 2)
        }
        let session = GrantTapAccountSession(accountId: "account", token: "token")
        let links = await AccountSpaceSync.recover(machines, session: session) { machine, received in
            XCTAssertEqual(received.accountId, session.accountId)
            if machine.name == "b" { throw AccountBridgeError.unavailable }
            return PairingFixture.pairing(room: machine.id)
        }
        XCTAssertEqual(Set(links.map(\.machineId)), Set([machines[0].id, machines[2].id]))
        XCTAssertEqual(Set(links.map { $0.pairing.room }), Set(links.map(\.machineId)))
    }

    func testAccountCanPlanOneThousandMachinesWithoutShowingOrPinningOneComputer() {
        let machines = (0..<1_001).map { index in
            AccountComputer(id: String(format: "%04d", index), name: "Mac \(index)",
                            createdAt: 100, lastSeenAt: index == 1_000 ? nil : 99_000)
        }
        let targets = AccountSpaceSync.availableMachines(
            machines, linkedMachineIds: ["0001"], nowMs: 100_000)
        XCTAssertEqual(targets.count, 999)
        XCTAssertFalse(targets.contains { $0.id == "0001" || $0.id == "1000" })
        XCTAssertEqual(targets.map(\.id), targets.map(\.id).sorted(by: >))
    }

    @MainActor
    func testAccountSpaceStartsEmptyThenRecoversAComputerWithoutChangingAccount() async throws {
        let previous = PairedConnectionStore.load()
        let phone = try NaclBox.keyPair()
        let mac = try NaclBox.keyPair()
        let room = String(repeating: "d", count: 32)
        let pairing = Pairing(relayUrl: "wss://127.0.0.1:9", room: room,
                              role: "phone", deviceName: "Mac D", senderId: "test-phone",
                              myPublicKey: phone.publicKey.base64EncodedString(),
                              mySecretKey: phone.secretKey.base64EncodedString(),
                              peerPublicKey: mac.publicKey.base64EncodedString())
        let machine = AccountComputer(id: String(repeating: "e", count: 32), name: "Mac D",
                                      createdAt: 1, lastSeenAt: Date().timeIntervalSince1970 * 1_000)
        let session = GrantTapAccountSession(accountId: "account-mesh", token: "test-session")
        let model = AppModel()
        model.connectionRegistry = .empty
        model.pairing = nil
        defer {
            model.relaysByRoom.values.forEach { $0.disconnect() }
            _ = PairedConnectionStore.save(previous)
        }

        try await model.synchronizeAccountSpace(session, loadComputers: { _ in [] },
            recover: { _, _ in XCTFail("An empty account has no computer to recover"); return [] },
            currentAccountId: { session.accountId })
        XCTAssertTrue(model.connectionRegistry.connections.isEmpty)

        try await model.synchronizeAccountSpace(session, loadComputers: { _ in [machine] },
            recover: { machines, received in
                XCTAssertEqual(machines.map(\.id), [machine.id])
                XCTAssertEqual(received.accountId, session.accountId)
                return [RecoveredAccountConnection(machineId: machine.id, pairing: pairing)]
            }, currentAccountId: { session.accountId })
        XCTAssertEqual(model.connectionRegistry.connections.count, 1)
        XCTAssertEqual(model.connectionRegistry.connections.first?.linkedMachineId, machine.id)
        XCTAssertEqual(model.pairing?.room, room)

        try await model.synchronizeAccountSpace(session, loadComputers: { _ in [machine] },
            recover: { _, _ in XCTFail("The same computer must not be linked twice"); return [] },
            currentAccountId: { session.accountId })
        XCTAssertEqual(model.connectionRegistry.connections.count, 1)
    }

    func testRecoveredMachineReferenceSurvivesPairingRefreshAndClearsWithAccount() {
        let pairing = PairingFixture.pairing(room: String(repeating: "a", count: 32))
        let reference = AccountMachineReference(accountId: "owner", machineId: "machine")
        let original = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        let linked = ConnectionRegistryLogic.noteAccountRecovery(
            original, roomId: pairing.room, peerPublicKey: pairing.peerPublicKey,
            reference: reference)
        XCTAssertEqual(linked.preferredId, original.preferredId)
        XCTAssertEqual(linked.connections.first?.linkedMachineId, "machine")
        let refreshed = ConnectionRegistryLogic.upsert(linked, pairing: pairing, prefer: false)
        XCTAssertEqual(refreshed.connections.first?.accountReference, reference)
        let cleared = ConnectionRegistryLogic.clearAccountLinks(refreshed, accountId: "owner")
        XCTAssertNil(cleared.connections.first?.linkedAccountId)
        XCTAssertEqual(cleared.preferredId, original.preferredId)
    }

    @MainActor
    func testRecoveredAccountRoutesMergeWithoutChangingPreferredComputer() throws {
        let previous = PairedConnectionStore.load()
        let phone = try NaclBox.keyPair()
        let mac = try NaclBox.keyPair()
        func pairing(_ letter: String) -> Pairing {
            Pairing(relayUrl: "wss://127.0.0.1:9", room: String(repeating: letter, count: 32),
                    role: "phone", deviceName: "Mac \(letter)", senderId: "test-phone",
                    myPublicKey: phone.publicKey.base64EncodedString(),
                    mySecretKey: phone.secretKey.base64EncodedString(),
                    peerPublicKey: mac.publicKey.base64EncodedString())
        }
        let first = pairing("a")
        let second = pairing("b")
        let third = pairing("c")
        let model = AppModel()
        defer {
            model.relaysByRoom.values.forEach { $0.disconnect() }
            _ = PairedConnectionStore.save(previous)
        }
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: first)
        let links = [RecoveredAccountConnection(machineId: "mac-b", pairing: second),
                     RecoveredAccountConnection(machineId: "mac-c", pairing: third)]

        XCTAssertFalse(model.addRecoveredAccountConnections([links[0], links[0]],
                                                          accountId: "account"))
        XCTAssertEqual(model.connectionRegistry.connections.count, 1)
        XCTAssertTrue(model.addRecoveredAccountConnections(links, accountId: "account"))
        XCTAssertEqual(model.connectionRegistry.preferredId, first.room)
        XCTAssertEqual(model.pairing?.room, first.room)
        XCTAssertEqual(Set(model.connectionRegistry.connections.map(\.id)),
                       Set([first.room, second.room, third.room]))
        XCTAssertEqual(model.connectionRegistry.connections.first(where: { $0.id == second.room })?
                           .accountReference,
                       AccountMachineReference(accountId: "account", machineId: "mac-b"))
        XCTAssertEqual(Set(model.relaysByRoom.keys), Set([second.room, third.room]))
        XCTAssertEqual(PairedConnectionStore.load(), model.connectionRegistry)
    }
}

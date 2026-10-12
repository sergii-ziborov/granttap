import XCTest
@testable import GrantTap

final class AccountDeviceRecoveryTests: XCTestCase {
    @MainActor
    func testAccountMachinesDoNotReappearAsSeparateLocalDevices() {
        let first = PairingFixture.pairing(room: String(repeating: "a", count: 32))
        let second = PairingFixture.pairing(room: String(repeating: "b", count: 32))
        let standalone = PairingFixture.pairing(room: String(repeating: "c", count: 32))
        var registry = ConnectionRegistryLogic.upsert(.empty, pairing: first)
        registry = ConnectionRegistryLogic.upsert(registry, pairing: second)
        registry = ConnectionRegistryLogic.upsert(registry, pairing: standalone)
        for pairing in [first, second] {
            registry = ConnectionRegistryLogic.noteAccountRecovery(registry,
                roomId: pairing.room, peerPublicKey: pairing.peerPublicKey,
                reference: .init(accountId: "account", machineId: "mac"))
        }
        XCTAssertEqual(AccountDeviceCatalog.otherConnections(in: registry,
            accountId: "account", machineIds: ["mac"]).map(\.id), [standalone.room])
        XCTAssertEqual(AccountDeviceCatalog.otherConnections(in: registry,
            accountId: "another", machineIds: []).count, 3)
    }
    @MainActor
    func testAccountCatalogDoesNotMixPasskeyRoutesFromDifferentAccounts() {
        let first = PairingFixture.pairing(room: String(repeating: "c", count: 32))
        let second = PairingFixture.pairing(room: String(repeating: "d", count: 32))
        var registry = ConnectionRegistryLogic.upsert(.empty, pairing: first)
        registry = ConnectionRegistryLogic.upsert(registry, pairing: second, prefer: false)
        registry = ConnectionRegistryLogic.noteAccountRecovery(registry,
            roomId: first.room, peerPublicKey: first.peerPublicKey,
            reference: AccountMachineReference(accountId: "first", machineId: "mac-1"))
        registry = ConnectionRegistryLogic.noteAccountRecovery(registry,
            roomId: second.room, peerPublicKey: second.peerPublicKey,
            reference: AccountMachineReference(accountId: "second", machineId: "mac-2"))

        XCTAssertEqual(AccountDeviceCatalog.rooms(in: registry, accountId: "first"), [first.room])
        XCTAssertEqual(AccountDeviceCatalog.rooms(in: registry, accountId: "second"), [second.room])
        XCTAssertTrue(AccountDeviceCatalog.rooms(in: registry, accountId: nil).isEmpty)
    }

    func testEveryStaleAccountDeviceNeedsRecoveryNotOnlyPreferred() {
        let now = Date().timeIntervalSince1970 * 1_000
        let first = PairingFixture.pairing(room: String(repeating: "a", count: 32))
        let second = PairingFixture.pairing(room: String(repeating: "b", count: 32))
        var registry = ConnectionRegistryLogic.upsert(.empty, pairing: first,
                                                      now: now - 600_000)
        registry = ConnectionRegistryLogic.upsert(registry, pairing: second,
                                                  prefer: false, now: now - 600_000)
        for (pairing, machine) in [(first, "machine-a"), (second, "machine-b")] {
            registry = ConnectionRegistryLogic.noteAccountRecovery(registry,
                roomId: pairing.room, peerPublicKey: pairing.peerPublicKey,
                reference: AccountMachineReference(accountId: "account", machineId: machine),
                nowMs: now - 600_000)
        }
        XCTAssertEqual(AccountSpaceSync.staleRoomsToRecover(registry,
            accountId: "account", nowMs: now), [first.room, second.room])
    }

    @MainActor
    func testQRAndPasskeyRoutesToOneMacContributeOneDeviceFacet() {
        let qr = PairingFixture.pairing(room: String(repeating: "q", count: 32))
        let passkey = PairingFixture.pairing(room: String(repeating: "p", count: 32))
        let reference = AccountMachineReference(accountId: "account", machineId: "one-mac")
        var registry = ConnectionRegistryLogic.upsert(.empty, pairing: qr, now: 1)
        registry = ConnectionRegistryLogic.noteAccountRecovery(registry,
            roomId: qr.room, peerPublicKey: qr.peerPublicKey, reference: reference, nowMs: 2)
        registry = ConnectionRegistryLogic.noteCatalog(registry,
            roomId: qr.room, generatedAt: 3, machineName: "Mac")
        registry = ConnectionRegistryLogic.upsert(registry, pairing: passkey,
            prefer: false, now: 4)
        registry = ConnectionRegistryLogic.noteAccountRecovery(registry,
            roomId: passkey.room, peerPublicKey: passkey.peerPublicKey,
            reference: reference, nowMs: 5)
        XCTAssertEqual(AccountDeviceCatalog.rooms(in: registry,
            accountId: "account", liveRooms: [passkey.room]), [qr.room],
            "keep the reported catalog until the replacement route reports")
        registry = ConnectionRegistryLogic.noteCatalog(registry,
            roomId: passkey.room, generatedAt: 6, machineName: "Mac")
        XCTAssertEqual(AccountDeviceCatalog.rooms(in: registry,
            accountId: "account", liveRooms: [passkey.room]), [passkey.room])
    }

    @MainActor
    func testOneMacChoosesFreshestCatalogThenRecoveryThenPairing() {
        let older = PairingFixture.pairing(room: String(repeating: "o", count: 32))
        let newer = PairingFixture.pairing(room: String(repeating: "n", count: 32))
        let reference = AccountMachineReference(accountId: "account", machineId: "same-mac")
        var registry = ConnectionRegistryLogic.upsert(.empty, pairing: older, now: 1)
        registry = ConnectionRegistryLogic.upsert(registry, pairing: newer,
                                                  prefer: false, now: 2)
        for pairing in [older, newer] {
            registry = ConnectionRegistryLogic.noteAccountRecovery(registry,
                roomId: pairing.room, peerPublicKey: pairing.peerPublicKey,
                reference: reference, nowMs: 3)
            registry = ConnectionRegistryLogic.noteCatalog(registry,
                roomId: pairing.room, generatedAt: 4, machineName: "Mac")
        }
        XCTAssertEqual(AccountDeviceCatalog.rooms(in: registry, accountId: "account"),
                       [newer.room], "equal reports and recovery prefer the newer pairing")

        registry = ConnectionRegistryLogic.noteAccountRecovery(registry,
            roomId: older.room, peerPublicKey: older.peerPublicKey,
            reference: reference, nowMs: 5)
        XCTAssertEqual(AccountDeviceCatalog.rooms(in: registry, accountId: "account"),
                       [older.room], "fresh recovery takes precedence over pairing age")

        registry = ConnectionRegistryLogic.noteCatalog(registry,
            roomId: newer.room, generatedAt: 6, machineName: "Mac")
        XCTAssertEqual(AccountDeviceCatalog.rooms(in: registry, accountId: "account"),
                       [newer.room], "a fresh report takes precedence over recovery age")
    }

    @MainActor
    func testAccountCatalogRefreshKeepsCapabilitiesAndRetainsChatsWhileTheNodeIsAbsent() {
        defer { SessionCatalogCache.clear() }
        let model = AppModel()
        let room = String(repeating: "r", count: 32)
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: PairingFixture.pairing(room: room))
        let now = Date().timeIntervalSince1970 * 1_000
        var first = SessionInfo(sessionId: "task", agent: "codex", projectId: "project",
            taskId: "task", computerId: "computer", title: "Real task", cwd: "/repo",
            state: "working", startedAt: now - 1, lastActivityAt: now,
            tokensSession: 0, tokensLastTurn: 0)
        first.skills = [SkillInfo(name: "review", description: nil)]
        model.captureAccountDeviceCatalog(SessionsStatus(machine: "Mac", sessions: [first],
            tokensRecent: 0, tokenWindowHours: 12, generatedAt: now), fromRoom: room)
        var lean = first
        lean.skills = nil
        model.captureAccountDeviceCatalog(SessionsStatus(machine: "Mac", sessions: [lean],
            tokensRecent: 0, tokenWindowHours: 12, generatedAt: now + 1), fromRoom: room)
        model.refreshAccountDeviceCatalog()
        XCTAssertEqual(model.sessions.map(\.sessionId), ["task"])
        XCTAssertEqual(model.sessions.first?.skills?.map(\.name), ["review"])

        model.accountDeviceCatalogs.removeAll()
        model.refreshAccountDeviceCatalog()
        XCTAssertEqual(model.sessions.map(\.sessionId), ["task"])
        XCTAssertTrue(model.sessionHistory.isEmpty)
    }

    @MainActor
    func testAccountSwitchCancelsRecoveryBeforeAndAfterAnOffer() async {
        let model = AppModel()
        let session = GrantTapAccountSession(accountId: "owner", token: "test-session")
        let now = Date().timeIntervalSince1970 * 1_000
        let older = AccountComputer(id: "older", name: "Older", createdAt: 1,
                                    lastSeenAt: now - 2_000)
        let newer = AccountComputer(id: "newer", name: "Newer", createdAt: 1,
                                    lastSeenAt: now - 1_000)
        XCTAssertEqual(AccountSpaceSync.availableMachines([older, newer],
            linkedMachineIds: [], nowMs: now).map(\.id), ["newer", "older"])

        do {
            try await model.synchronizeAccountSpace(session,
                loadComputers: { _ in [newer] },
                recover: { _, _ in XCTFail("Account changed before recovery"); return [] },
                currentAccountId: { "another" })
            XCTFail("A different account cannot inherit this machine")
        } catch is CancellationError { }
        catch { XCTFail("Unexpected recovery error: \(error)") }

        var identityChecks = 0
        do {
            try await model.synchronizeAccountSpace(session,
                loadComputers: { _ in [newer] },
                recover: { _, _ in [RecoveredAccountConnection(machineId: newer.id,
                    pairing: PairingFixture.pairing(room: String(repeating: "r", count: 32)))] },
                currentAccountId: {
                    identityChecks += 1
                    return identityChecks == 1 ? session.accountId : "another"
                })
            XCTFail("An account switch during recovery must discard the offer")
        } catch is CancellationError { }
        catch { XCTFail("Unexpected recovery error: \(error)") }
        XCTAssertTrue(model.connectionRegistry.connections.isEmpty)
        model.stopAccountSpaceSync()
        XCTAssertNil(model.accountSpaceSyncTask)
        XCTAssertNil(model.accountSpaceSyncGeneration)
    }
}

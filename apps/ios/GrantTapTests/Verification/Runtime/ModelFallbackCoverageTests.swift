import XCTest
@testable import GrantTap

final class ModelFallbackCoverageTests: XCTestCase {
    @MainActor
    func testCatalogTitleClassifierCoversOpaqueAndReadableBoundaries() {
        let uuid = "123e4567-e89b-12d3-a456-426614174000"
        XCTAssertFalse(AppModel.looksLikeSessionId(nil))
        XCTAssertFalse(AppModel.looksLikeSessionId("  "))
        XCTAssertTrue(AppModel.looksLikeSessionId(uuid))
        XCTAssertFalse(AppModel.looksLikeSessionId("ordinary-task"))

        XCTAssertFalse(AppModel.looksLikeOpaqueCipherTitle(nil))
        XCTAssertFalse(AppModel.looksLikeOpaqueCipherTitle("Readable task title"))
        XCTAssertTrue(AppModel.looksLikeOpaqueCipherTitle(uuid))
        XCTAssertTrue(AppModel.looksLikeOpaqueCipherTitle(String(repeating: "a", count: 28)))
        XCTAssertFalse(AppModel.looksLikeOpaqueCipherTitle("short-token"))
        XCTAssertFalse(AppModel.looksLikeOpaqueCipherTitle("abcdefghijklmnopqr!tuv"))
        XCTAssertTrue(AppModel.looksLikeOpaqueCipherTitle("1234567890123456789012345678"))
        XCTAssertTrue(AppModel.looksLikeOpaqueCipherTitle("bcdfghjklmnpqrstvwxyzBCDF"))
        XCTAssertFalse(AppModel.looksLikeOpaqueCipherTitle("thisisareadablelowercaseword"))
        XCTAssertTrue(AppModel.looksLikeOpaqueCipherTitle("aBCDFGHJKLMNPQRSTVWXYZbcdf"))

        XCTAssertFalse(AppModel.isCodeBlobCatalogTitle(sessionId: uuid, title: nil))
        XCTAssertTrue(AppModel.isCodeBlobCatalogTitle(sessionId: "native-id", title: "native-id"))
        XCTAssertTrue(AppModel.isCodeBlobCatalogTitle(sessionId: "abcdefgh-rest", title: "ABCDEFGH"))
        XCTAssertFalse(AppModel.isCodeBlobCatalogTitle(
            sessionId: "native-id", title: "Implement pairing flow"
        ))
    }

    func testWatchPayloadDefaultsDecodeWithoutInventingState() throws {
        let approval = WatchApproval(
            id: "ask", agent: "codex", title: "Allow?", command: nil,
            risk: "low", cwd: nil, sessionId: nil
        )
        XCTAssertNil(approval.waitingForMachine)
        let session = WatchSession(
            id: "task", agent: "codex", title: "Task", state: "working",
            tokensSession: 1, tokensLastTurn: 1, elapsedSec: 2
        )
        XCTAssertNil(session.contextTokensUsed)
        XCTAssertNil(session.contextWindow)
        XCTAssertNil(session.lastActivityAt)
        XCTAssertEqual(WatchAgentIntegration(
            agent: "codex", installed: true, hookConfigured: true
        ).id, "codex")

        let empty = try JSONDecoder().decode(WatchState.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, WatchState())
        let populated = WatchState(
            approvals: [approval], questions: [WatchQuestion(id: "q", text: "Why?", sessionId: nil)],
            sessions: [session], activities: [WatchActivity(
                sessionId: "task", agent: "codex", state: "working",
                entries: [WatchActivityEntry(id: "e", kind: "message", text: "Hi", createdAt: 1)]
            )], agents: [WatchAgentIntegration(
                agent: "codex", installed: true, hookConfigured: true
            )], machine: "Mac", connected: true, stamp: 3
        )
        let roundTrip = try JSONDecoder().decode(
            WatchState.self, from: JSONEncoder().encode(populated)
        )
        XCTAssertEqual(roundTrip, populated)
    }

    func testMachineAndSessionStatusDecodeEveryMissingFallback() throws {
        let load = try JSONDecoder().decode(MachineLoad.self, from: Data("{}".utf8))
        XCTAssertEqual(load, MachineLoad(
            machine: "", monitorCpuPercent: 0, monitorMemoryBytes: 0,
            agents: [], generatedAt: 0
        ))
        let sample = try JSONDecoder().decode(
            AgentLoadSample.self, from: Data("{}".utf8)
        )
        XCTAssertEqual(sample, AgentLoadSample(agent: ""))
        XCTAssertEqual(AgentIntegrationInfo(
            agent: "claude", installed: true, hookConfigured: false
        ).id, "claude")

        let json = #"{"sessions":[7,{"sessionId":"kept"}],"history":7,"activities":[7,{"sessionId":"kept","entries":[]}]}"#
        let status = try JSONDecoder().decode(SessionsStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.sessions.map(\.sessionId), ["kept"])
        XCTAssertEqual(status.history, [])
        XCTAssertEqual(status.activities?.map(\.sessionId), ["kept"])
    }

    @MainActor
    func testLegacyPairingFacadePersistsLoadsAndRemovesOneValidSimulatorPairing() throws {
        let original = PairedConnectionStore.load()
        defer { XCTAssertTrue(PairedConnectionStore.save(original)) }
        let key = Data(repeating: 19, count: 32).base64EncodedString()
        let pairing = Pairing(
            relayUrl: "wss://relay.granttap.app", room: String(repeating: "a", count: 32),
            role: "phone", deviceName: "Coverage Mac", senderId: "coverage-sender",
            myPublicKey: key, mySecretKey: key, peerPublicKey: key
        )
        XCTAssertTrue(pairing.save())
        XCTAssertEqual(Pairing.load(), pairing)
        Pairing.remove()
        XCTAssertNil(Pairing.load())
    }

    func testPairingKeychainAddsUpdatesLoadsAndRemovesBoundedData() {
        let service = "com.ziborov.granttap.coverage.\(UUID().uuidString)"
        defer { KeychainPairing.remove(service: service) }
        XCTAssertNil(KeychainPairing.load(service: service))
        XCTAssertTrue(KeychainPairing.save(Data("first".utf8), service: service))
        XCTAssertEqual(KeychainPairing.load(service: service), Data("first".utf8))
        XCTAssertTrue(KeychainPairing.save(Data("second".utf8), service: service))
        XCTAssertEqual(KeychainPairing.load(service: service), Data("second".utf8))
        KeychainPairing.remove(service: service)
        XCTAssertNil(KeychainPairing.load(service: service))
    }

    func testConnectionRegistryReplacementPeerRotationAndDecodeFallbacks() throws {
        let first = fallbackPairing(room: "a", peerByte: 1, device: "First")
        var registry = ConnectionRegistryLogic.upsert(
            .empty, pairing: first, mode: .replaceAll, label: "  Custom  ", now: 10
        )
        XCTAssertEqual(registry.preferred?.displayName, "Custom")
        registry.connections[0].lastCatalogAt = 9
        registry.connections[0].lastMachineName = "Measured"

        var renamed = first
        renamed.deviceName = ""
        registry = ConnectionRegistryLogic.upsert(
            registry, pairing: renamed, label: " ", prefer: false, now: 20
        )
        XCTAssertEqual(registry.connections[0].label, "Custom")
        XCTAssertEqual(registry.connections[0].lastCatalogAt, 9)

        let rotated = fallbackPairing(room: "a", peerByte: 2, device: "Rotated")
        registry = ConnectionRegistryLogic.upsert(
            registry, pairing: rotated, prefer: false, now: 30
        )
        XCTAssertEqual(registry.connections[0].lastCatalogAt, 0)
        XCTAssertEqual(registry.connections[0].lastMachineName, "")

        let bare = try JSONEncoder().encode(rotated)
        XCTAssertEqual(PairedConnectionStore.decodeRegistry(bare)?.preferred?.pairing, rotated)
        XCTAssertNil(PairedConnectionStore.decodeRegistry(Data("invalid".utf8)))

        let connectionObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(registry.connections[0])
        ) as? [String: Any])
        let file = try JSONSerialization.data(withJSONObject: [
            "v": 1, "preferredId": "missing", "connections": [connectionObject],
        ])
        let decoded = try XCTUnwrap(PairedConnectionStore.decodeRegistry(file))
        XCTAssertEqual(decoded.preferredId, decoded.connections[0].id)
    }

    @MainActor
    func testConnectionStoreMigratesOneLegacyKeychainPairing() throws {
        let original = PairedConnectionStore.load()
        PairedConnectionStore.removeAll()
        defer {
            PairedConnectionStore.removeAll()
            XCTAssertTrue(PairedConnectionStore.save(original))
        }
        let legacy = fallbackPairing(room: "b", peerByte: 3, device: "Legacy")
        XCTAssertTrue(KeychainPairing.save(
            try JSONEncoder().encode(legacy), service: Pairing.keychainService
        ))
        let migrated = PairedConnectionStore.load()
        XCTAssertEqual(migrated.preferred?.pairing, legacy)
        XCTAssertNil(KeychainPairing.load(service: Pairing.keychainService))
    }

    @MainActor
    func testConnectionStoreMigratesRetiredRelayWithoutChangingIdentity() throws {
        let original = PairedConnectionStore.load()
        PairedConnectionStore.removeAll()
        defer {
            PairedConnectionStore.removeAll()
            XCTAssertTrue(PairedConnectionStore.save(original))
        }
        var retired = fallbackPairing(room: "c", peerByte: 4, device: "Retired relay")
        retired.relayUrl = "wss://granttap-relay.sergii-ziborov.workers.dev"
        let registry = ConnectionRegistryLogic.upsert(.empty, pairing: retired)
        XCTAssertTrue(PairedConnectionStore.save(registry))

        let migrated = try XCTUnwrap(PairedConnectionStore.load().preferred?.pairing)
        XCTAssertEqual(migrated.relayUrl, "wss://relay.granttap.com")
        XCTAssertEqual(migrated.room, retired.room)
        XCTAssertEqual(migrated.mySecretKey, retired.mySecretKey)
        XCTAssertEqual(PairedConnectionStore.load().preferred?.pairing, migrated)
    }

    private func fallbackPairing(
        room: Character, peerByte: UInt8, device: String
    ) -> Pairing {
        let own = Data(repeating: 7, count: 32).base64EncodedString()
        let peer = Data(repeating: peerByte, count: 32).base64EncodedString()
        return Pairing(
            relayUrl: "wss://relay.granttap.app", room: String(repeating: room, count: 32),
            role: "phone", deviceName: device, senderId: "fallback",
            myPublicKey: own, mySecretKey: own, peerPublicKey: peer
        )
    }
}

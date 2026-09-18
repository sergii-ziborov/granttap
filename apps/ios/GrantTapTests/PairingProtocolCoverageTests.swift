import XCTest
@testable import GrantTap

final class PairingProtocolCoverageTests: XCTestCase {
    func testSecurePairingLinksAcceptV2UrisAndManualTokensAndRejectMalformedInputs() throws {
        let mailbox = String(repeating: "a", count: Pairing.mailboxLength)
        let transferKey = base64URL(Data(repeating: 7, count: 32))
        let relay = "wss://relay.granttap.app"
        for scheme in ["granttap", "nodvox"] {
            let uri = "\(scheme)://pair-v2?v=2&u=\(relay)&m=\(mailbox)&k=\(transferKey)"
            let link = try XCTUnwrap(Pairing.secureLink(fromURI: uri))
            XCTAssertEqual(link.relayBase, relay)
            XCTAssertEqual(link.mailboxId, mailbox)
            XCTAssertEqual(link.transferKey, transferKey)
        }
        XCTAssertNotNil(Pairing.secureLink(
            fromURI: "granttap://pair?v=2&u=\(relay)&m=\(mailbox)&k=\(transferKey)"
        ))
        let manual = try XCTUnwrap(Pairing.secureLink(
            relayBase: relay,
            manualToken: "  \(mailbox.uppercased()).\(transferKey)  "
        ))
        XCTAssertEqual(manual.mailboxId, mailbox)
        let retired = try XCTUnwrap(Pairing.secureLink(
            relayBase: "https://granttap-relay.sergii-ziborov.workers.dev",
            manualToken: "\(mailbox).\(transferKey)"
        ))
        XCTAssertEqual(retired.relayBase, "https://relay.granttap.com")

        for invalid in [
            "https://pair-v2?v=2&u=x&m=\(mailbox)&k=\(transferKey)",
            "granttap://other?v=2&u=x&m=\(mailbox)&k=\(transferKey)",
            "granttap://pair-v2?v=1&u=x&m=\(mailbox)&k=\(transferKey)",
            "granttap://pair-v2?v=2&u=x&m=short&k=\(transferKey)",
            "granttap://pair-v2?v=2&u=x&m=\(mailbox)&k=bad",
        ] {
            XCTAssertNil(Pairing.secureLink(fromURI: invalid), invalid)
        }
        XCTAssertNil(Pairing.secureLink(relayBase: relay, manualToken: "missing-dot"))
        XCTAssertNil(Pairing.secureLink(relayBase: relay, manualToken: "short.bad"))
    }

    func testLegacyPairingUriDecodesCanonicalKeysAndRejectsV2AndBadHosts() throws {
        let key = Data(repeating: 8, count: 32).base64EncodedString()
        let room = String(repeating: "b", count: 32)
        var components = URLComponents()
        components.scheme = "granttap"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "u", value: "wss://relay.granttap.app"),
            URLQueryItem(name: "r", value: room),
            URLQueryItem(name: "s", value: base64URL(Data(repeating: 8, count: 32))),
            URLQueryItem(name: "p", value: base64URL(Data(repeating: 8, count: 32))),
            URLQueryItem(name: "k", value: base64URL(Data(repeating: 8, count: 32))),
            URLQueryItem(name: "i", value: "phone-id"),
            URLQueryItem(name: "a", value: String(repeating: "c", count: 64)),
        ]
        let pairing = try XCTUnwrap(Pairing.fromURI(try XCTUnwrap(components.string)))
        XCTAssertEqual(pairing.room, room)
        XCTAssertEqual(pairing.myPublicKey, key)
        XCTAssertEqual(pairing.senderId, "phone-id")
        XCTAssertEqual(pairing.pushAuth, String(repeating: "c", count: 64))

        components.queryItems?[1] = URLQueryItem(
            name: "u", value: "wss://granttap-relay.sergii-ziborov.workers.dev"
        )
        let retired = try XCTUnwrap(Pairing.fromURI(try XCTUnwrap(components.string)))
        XCTAssertEqual(retired.relayUrl, "wss://relay.granttap.com")

        XCTAssertNil(Pairing.fromURI("granttap://pair-v2?v=2"))
        XCTAssertNil(Pairing.fromURI("granttap://other?v=1"))
        XCTAssertNil(Pairing.fromURI("https://pair?v=1"))
        XCTAssertNil(Pairing.fromURI("granttap://pair?v=1&u=ws://example.com"))
    }

    func testConfigurationFactoriesAndLegacyApprovalMetadataRoundTrip() throws {
        XCTAssertEqual(AutoAcceptLevel.parse(nil), .ask)
        XCTAssertEqual(AutoAcceptLevel.parse("invalid"), .ask)
        for level in AutoAcceptLevel.allCases {
            XCTAssertEqual(AutoAcceptLevel.parse(level.rawValue), level)
            XCTAssertEqual(level.id, level.rawValue)
            XCTAssertFalse(level.title.isEmpty)
            XCTAssertFalse(level.blurb.isEmpty)
        }
        let config = ConfigSet(
            type: "config.set", enabled: true, excludeSession: "one",
            includeSession: nil, autoAcceptDefault: "ask",
            autoAcceptSession: AutoAcceptSessionSet(sessionId: "one", level: nil),
            autoAcceptPaused: false, createdAt: 1
        )
        let decoded = try JSONDecoder().decode(
            ConfigSet.self, from: JSONEncoder().encode(config)
        )
        XCTAssertEqual(decoded.autoAcceptSession?.sessionId, "one")
        XCTAssertNil(decoded.autoAcceptSession?.level)

        let decision = Payloads.decision("request", "allow", by: "phone", sessionId: "session")
        XCTAssertEqual(decision.requestId, "request")
        XCTAssertEqual(decision.decision, "allow")
        XCTAssertEqual(decision.sessionId, "session")
        XCTAssertNil(Payloads.hello("Phone").recoverPeer)
        XCTAssertEqual(Payloads.hello("Phone", recoverPeer: true).recoverPeer, true)
        let attachment = UserAttachment(
            name: "note.txt", mimeType: "text/plain",
            data: Data("note".utf8).base64EncodedString()
        )
        let message = Payloads.message(
            "Continue", messageId: "message", agent: "codex", cwd: "/repo",
            sessionId: "session", requestId: nil, attachments: [attachment],
            preferredMcp: "github", skill: "review", model: "gpt",
            permissionMode: "workspace-write"
        )
        XCTAssertEqual(message.attachments?.count, 1)
        XCTAssertEqual(message.preferredMcp, "github")
        XCTAssertNil(Payloads.message(
            "Empty", messageId: "empty", agent: nil, cwd: nil,
            sessionId: nil, requestId: nil
        ).attachments)
    }

    func testLinkedComputerNamesPreferredFallbackAndReplaceMode() {
        let pairing = rawPairing(room: "room", device: " Device ")
        let custom = LinkedComputer(
            id: "room", pairing: pairing, label: " Custom ", addedAt: 1,
            lastCatalogAt: 2, lastMachineName: "Machine"
        )
        XCTAssertEqual(custom.displayName, "Custom")
        var device = custom
        device.label = " "
        XCTAssertEqual(device.displayName, "Device")
        device.pairing.deviceName = " "
        XCTAssertEqual(device.displayName, "Machine")
        device.lastMachineName = " "
        XCTAssertEqual(device.displayName, "PC room")

        let registry = ConnectionRegistry(connections: [custom], preferredId: "missing")
        XCTAssertEqual(registry.preferred?.id, "room")
        let replaced = ConnectionRegistryLogic.upsert(
            registry, pairing: rawPairing(room: "next", device: "Next"),
            mode: .replaceAll, label: " Replacement ", now: 3
        )
        XCTAssertEqual(replaced.connections.map(\.id), ["next"])
        XCTAssertEqual(replaced.preferredId, "next")
        XCTAssertNil(ConnectionRegistryLogic.setPreferred(replaced, roomId: "missing"))
    }

    @MainActor
    func testScannedComputerJoinsThePhoneRoomInsteadOfMintingASecondRoom() async {
        let stored = PairedConnectionStore.load()
        PairedConnectionStore.removeAll()
        defer {
            PairedConnectionStore.removeAll()
            if !stored.connections.isEmpty { _ = PairedConnectionStore.save(stored) }
        }
        let existing = validPairing()
        var candidate = validPairing()
        candidate.room = String(repeating: "c", count: 32)
        candidate.peerPublicKey = Data(repeating: 9, count: 32).base64EncodedString()
        XCTAssertTrue(PairingJoinLogic.shouldJoinExistingRoom(
            existing: existing, candidate: candidate, phoneHasLivePeer: true
        ))
        XCTAssertFalse(PairingJoinLogic.shouldJoinExistingRoom(
            existing: existing, candidate: candidate, phoneHasLivePeer: false
        ))
        XCTAssertFalse(PairingJoinLogic.shouldJoinExistingRoom(existing: existing, candidate: existing))
        var existingWithoutAuth = existing
        existingWithoutAuth.pushAuth = nil
        var candidateWithAuth = candidate
        candidateWithAuth.pushAuth = String(repeating: "ab", count: 32)
        let remembered = PairingJoinLogic.remembered(
            existingWithoutAuth, machinePublicKey: candidate.peerPublicKey, from: candidateWithAuth
        )
        XCTAssertEqual(remembered.room, existing.room)
        XCTAssertEqual(remembered.extraPeerPublicKeys, [candidate.peerPublicKey])
        XCTAssertEqual(remembered.pushAuth, candidateWithAuth.pushAuth)
        let join = PairingJoinLogic.payload(existing: existing, machinePublicKey: candidate.peerPublicKey, now: 7)
        XCTAssertEqual(join.type, "pairing.join")
        XCTAssertEqual(join.room, existing.room)
        XCTAssertEqual(join.phoneCfg.extraPeerPublicKeys, [candidate.peerPublicKey])

        let model = AppModel()
        model.loadConnectionRegistry()
        XCTAssertTrue(model.addConnection(existing))
        let now = Date().timeIntervalSince1970 * 1_000
        model.roomRuntime[existing.room] = AppModel.RoomRuntime(
            socketUp: true, socketUpSince: now, lastHeartbeatAt: now
        )
        let joined = await model.admitScannedComputer(candidate) { _, _ in true }
        XCTAssertTrue(joined)
        XCTAssertEqual(model.connectionRegistry.connections.count, 1)
        XCTAssertEqual(model.connectionRegistry.preferredId, existing.room)
        XCTAssertEqual(
            model.connectionRegistry.preferred?.pairing.extraPeerPublicKeys,
            [candidate.peerPublicKey]
        )
        model.roomRuntime[existing.room] = AppModel.RoomRuntime(
            socketUp: true, socketUpSince: now, lastHeartbeatAt: now
        )
        let refused = await model.admitScannedComputer(candidate) { _, _ in false }
        XCTAssertFalse(refused)
        XCTAssertEqual(model.connectionRegistry.connections.count, 1)
    }

    @MainActor
    func testOfflinePhoneAdoptsTheWebsiteRoomInsteadOfKeepingAStaleOne() async {
        let stored = PairedConnectionStore.load()
        PairedConnectionStore.removeAll()
        defer {
            PairedConnectionStore.removeAll()
            if !stored.connections.isEmpty { _ = PairedConnectionStore.save(stored) }
        }
        let stale = validPairing()
        var website = validPairing()
        website.room = String(repeating: "d", count: 32)
        website.peerPublicKey = Data(repeating: 7, count: 32).base64EncodedString()
        let model = AppModel()
        model.loadConnectionRegistry()
        XCTAssertTrue(model.addConnection(stale))
        let adopted = await model.admitScannedComputer(website) { _, _ in
            XCTFail("offline phone must not send pairing.join")
            return false
        }
        XCTAssertTrue(adopted)
        XCTAssertEqual(model.connectionRegistry.preferredId, website.room)
    }

    @MainActor
    func testPairingSheetHandlesManualSecureAndPersistenceOutcomes() async throws {
        let model = AppModel()
        let valid = validPairing()
        var invalid = valid
        invalid.role = "machine"
        var rejected = valid
        rejected.senderId = "d"
        var accepted: [Pairing] = []
        let fetched = expectation(description: "secure pairing outcomes")
        fetched.expectedFulfillmentCount = 4
        let sheet = PairingSheet(
            secureToken: "invalid", modelOverride: model,
            securePairingFetcher: { link in
                defer { fetched.fulfill() }
                switch link.mailboxId.first {
                case "a": return .failure(.codeExpiredOrUsed)
                case "b": return .success(invalid)
                default:
                    var pairing = valid
                    pairing.senderId = String(link.mailboxId.prefix(1))
                    return .success(pairing)
                }
            },
            pairingConsumer: {
                accepted.append($0)
                return $0.senderId != "d"
            },
            onPaired: {}
        )

        sheet.connectByToken()
        sheet.apply("not a pairing")
        sheet.apply(try pairingJSON(invalid))
        sheet.apply(try pairingJSON(rejected))
        sheet.apply(try pairingJSON(valid))
        XCTAssertEqual(accepted.count, 2)

        for character in ["a", "b", "c"] {
            sheet.connect(try secureLink(character: character))
        }
        sheet.apply(try secureURI(character: "d"))
        await fulfillment(of: [fetched], timeout: 2)
        await Task.yield()
        XCTAssertEqual(accepted.count, 4)
    }

    private func rawPairing(room: String, device: String) -> Pairing {
        Pairing(
            relayUrl: "wss://relay.granttap.app", room: room, role: "phone",
            deviceName: device, senderId: "phone", myPublicKey: "key",
            mySecretKey: "key", peerPublicKey: "key"
        )
    }

    private func validPairing() -> Pairing {
        let key = Data(repeating: 8, count: 32).base64EncodedString()
        return Pairing(
            relayUrl: "wss://relay.granttap.app",
            room: String(repeating: "b", count: 32), role: "phone",
            deviceName: "Test Mac", senderId: "phone",
            myPublicKey: key, mySecretKey: key, peerPublicKey: key
        )
    }

    private func pairingJSON(_ pairing: Pairing) throws -> String {
        String(decoding: try JSONEncoder().encode(pairing), as: UTF8.self)
    }

    private func secureLink(character: String) throws -> Pairing.SecureLink {
        try XCTUnwrap(Pairing.secureLink(
            relayBase: "wss://relay.granttap.app",
            manualToken: "\(String(repeating: character, count: Pairing.mailboxLength)).\(base64URL(Data(repeating: 9, count: 32)))"
        ))
    }

    private func secureURI(character: String) throws -> String {
        let link = try secureLink(character: character)
        return "granttap://pair-v2?v=2&u=\(link.relayBase)&m=\(link.mailboxId)&k=\(link.transferKey)"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

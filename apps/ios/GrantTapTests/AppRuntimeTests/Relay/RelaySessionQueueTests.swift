import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    func testSessionQueueCoalescesControlsBoundsCapacityAndExpiresEntries() throws {
        let client = RelayClient(pairing: testPairing(room: "room-a"))
        let mcp = sessionPayload(
            type: "session.mcp.set", sessionId: "session-a", extra: ["serverName": "github"]
        )
        var firstError: Error?
        let first = client.enqueuePendingSessionPayload(
            plain: mcp, room: "room-a", sessionId: "session-a", ttl: 60,
            deliveryId: "first", completion: { firstError = $0 }
        )
        assertQueued(first, needsSubscription: true)
        XCTAssertEqual(client.pendingSessionIds(room: "room-a"), ["session-a"])

        let replacement = client.enqueuePendingSessionPayload(
            plain: mcp, room: "room-a", sessionId: "session-a", ttl: 60,
            deliveryId: "second", completion: nil
        )
        assertQueued(replacement, needsSubscription: false)
        XCTAssertTrue(firstError is RelaySendError)

        let tooLarge = Data(repeating: 1, count: RelayClient.maxPendingSessionPayloadSize + 1)
        assertRejected(client.enqueuePendingSessionPayload(
            plain: tooLarge, room: "room-a", sessionId: "large", ttl: 60,
            deliveryId: nil, completion: nil
        ))
        assertRejected(client.enqueuePendingSessionPayload(
            plain: mcp, room: "room-a", sessionId: "expired", ttl: 0,
            deliveryId: nil, completion: nil
        ))

        client.pendingSessionPayloads.removeAll()
        client.latestSessionPayloadIds.removeAll()
        for index in 0..<RelayClient.maxPendingSessionPayloads {
            let unique = sessionPayload(
                type: "custom.\(index)", sessionId: "session-\(index)", extra: [:]
            )
            assertQueued(client.enqueuePendingSessionPayload(
                plain: unique, room: "room-a", sessionId: "session-\(index)", ttl: 60,
                deliveryId: nil, completion: nil
            ), needsSubscription: true)
        }
        assertRejected(client.enqueuePendingSessionPayload(
            plain: sessionPayload(type: "overflow", sessionId: "overflow", extra: [:]),
            room: "room-a", sessionId: "overflow", ttl: 60,
            deliveryId: nil, completion: nil
        ))

        var expiryError: Error?
        client.pendingSessionPayloads.removeAll()
        client.latestSessionPayloadIds.removeAll()
        _ = client.enqueuePendingSessionPayload(
            plain: mcp, room: "room-a", sessionId: "session-a", ttl: 60,
            deliveryId: nil, completion: { expiryError = $0 }
        )
        client.sessionStateLock.lock()
        let expired = client.pruneExpiredPendingSessionPayloadsLocked(
            now: Date().timeIntervalSince1970 + 120
        )
        client.sessionStateLock.unlock()
        client.finishExpiredPendingSessionPayloads(expired)
        XCTAssertEqual(expired.count, 1)
        XCTAssertTrue(expiryError is RelaySendError)
    }

    func testSessionQueueRecognizesControlKindsAndStripsNulls() throws {
        let cases: [(String, [String: String], RelayClient.SessionPayloadCoalescingKey?)] = [
            ("session.access.set", [:], .access),
            ("session.mcp.set", ["serverName": "github"], .mcp("github")),
            ("session.skill.set", ["skillName": "documents"], .skill("documents")),
            ("session.shell.set", [:], .shell),
            ("session.compact", [:], .compact),
            ("project.policy.set", [:], .projectPolicy),
            ("unknown", [:], nil),
            ("session.mcp.set", [:], nil),
            ("session.skill.set", [:], nil),
        ]
        for (type, extra, expected) in cases {
            let data = sessionPayload(type: type, sessionId: "session-a", extra: extra)
            XCTAssertEqual(RelayClient.sessionPayloadCoalescingKey(data), expected)
        }
        XCTAssertNil(RelayClient.sessionPayloadCoalescingKey(Data("not json".utf8)))

        let stripped = RelayClient.stripNulls([
            "keep": "value", "drop": NSNull(),
            "nested": ["drop": NSNull(), "number": 1],
            "array": ["first", NSNull(), ["drop": NSNull(), "last": true]],
        ]) as? [String: Any]
        XCTAssertNil(stripped?["drop"])
        XCTAssertEqual((stripped?["nested"] as? [String: Any])?["number"] as? Int, 1)
        XCTAssertEqual((stripped?["array"] as? [Any])?.count, 2)

        struct OptionalPayload: Encodable { let type: String; let value: String? }
        let encoded = try RelayClient.encodeOmittingNulls(
            OptionalPayload(type: "sample", value: nil)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(object["type"] as? String, "sample")
        XCTAssertNil(object["value"])
    }

    func testSessionSendRejectsEncodingAndScopeBeforeTransport() {
        let client = RelayClient(pairing: testPairing(room: "room-a"))
        struct Broken: Codable {
            init() {}
            init(from decoder: Decoder) throws {
                throw NSError(domain: "test", code: 2)
            }
            func encode(to encoder: Encoder) throws {
                throw NSError(domain: "test", code: 1)
            }
        }
        var encodingError: Error?
        client.sendSession(payload: Broken(), sessionId: "session-a") {
            encodingError = $0
        }
        XCTAssertTrue(encodingError is RelaySendError)

        var scopeError: Error?
        let wrong = SessionSubscription(
            type: "session.subscribe", sessionId: "different", active: true, createdAt: 1
        )
        client.sendSession(payload: wrong, sessionId: "session-a") { scopeError = $0 }
        XCTAssertTrue(scopeError is RelaySendError)
        client.resumePendingSessionPayloads()
        client.flushPendingSessionPayloads(sessionId: "session-a", room: "other-room")
        XCTAssertNil(client.sessionKey(for: "missing"))
    }

    func testSessionTransportCompletionRequeueAndTerminalRejections() {
        let client = RelayClient(pairing: testPairing(room: "room-a"))
        let plain = sessionPayload(
            type: "session.mcp.set", sessionId: "session-a", extra: ["serverName": "github"]
        )
        var result: Error?
        var completed = false
        let entry = pendingEntry(plain: plain) { error in
            result = error
            completed = true
        }
        client.latestSessionPayloadIds[entry.queueKey] = entry.id
        client.completeSessionPayloadSend(entry, error: nil)
        XCTAssertTrue(completed)
        XCTAssertNil(result)

        completed = false
        let terminal = pendingEntry(plain: plain) { error in
            result = error
            completed = true
        }
        client.latestSessionPayloadIds[terminal.queueKey] = terminal.id
        client.completeSessionPayloadSend(terminal, error: RelaySendError.encryption)
        XCTAssertTrue(completed)
        XCTAssertTrue(result is RelaySendError)

        result = nil
        let disconnected = pendingEntry(plain: plain) { result = $0 }
        client.latestSessionPayloadIds[disconnected.queueKey] = disconnected.id
        client.completeSessionPayloadSend(disconnected, error: RelaySendError.disconnected)
        XCTAssertNil(result)
        XCTAssertEqual(client.pendingSessionPayloads[disconnected.queueKey]?.id, disconnected.id)
        XCTAssertNotNil(client.sessionSubscriptionRetryTokens["session-a"])

        let wrongRoom = pendingEntry(plain: plain, room: "other") { result = $0 }
        client.requeueFailedSessionPayload(wrongRoom)
        XCTAssertTrue(result is RelaySendError)
        let expired = pendingEntry(
            plain: plain, expiresAt: Date().timeIntervalSince1970 - 1
        ) { result = $0 }
        client.requeueFailedSessionPayload(expired)
        XCTAssertTrue(result is RelaySendError)

        let superseded = pendingEntry(plain: plain) { result = $0 }
        client.latestSessionPayloadIds[superseded.queueKey] = UUID()
        client.requeueFailedSessionPayload(superseded)
        XCTAssertTrue(result is RelaySendError)
        client.cancelSessionKeySubscriptionRetry(sessionId: "session-a")
        XCTAssertNil(client.sessionSubscriptionRetryTokens["session-a"])
    }

    func testSessionRetryGuardsPlainSendFailuresAndRelayLifecycleErrors() {
        let client = RelayClient(pairing: testPairing(room: "room-a"))
        let plain = sessionPayload(type: "session.shell.set", sessionId: "session-a", extra: [:])
        var error: Error?
        client.sendSessionPlain(
            plain, sessionId: "wrong", key: "invalid", ttl: nil,
            deliveryId: nil, completion: { error = $0 }
        )
        XCTAssertTrue(error is RelaySendError)
        error = nil
        client.sendSessionPlain(
            plain, sessionId: "session-a", key: "invalid", ttl: nil,
            deliveryId: nil, completion: { error = $0 }
        )
        XCTAssertTrue(error is RelaySendError)

        client.ensureSessionKeySubscription(sessionId: "missing", room: "room-a", sendNow: false)
        client.scheduleSessionQueueRetry(sessionId: "missing", room: "other")
        client.scheduleSessionQueueRetry(sessionId: "missing", room: "room-a")
        client.fireSessionQueueRetry(sessionId: "missing", room: "room-a", token: UUID())
        XCTAssertTrue(client.pendingSessionIds(room: "other").isEmpty)

        let descriptions: [RelaySendError] = [
            .disconnected, .encoding, .encryption, .missingSessionKey,
            .invalidSessionScope, .sessionQueueFull, .sessionPayloadTooLarge,
            .sessionPayloadExpired, .supersededSessionPayload,
        ]
        XCTAssertTrue(descriptions.allSatisfy { !($0.errorDescription ?? "").isEmpty })

        let inert = RelayClient(pairing: testPairing(room: "room-a"))
        var edges: [Bool] = []
        inert.onConnectionChange = { edges.append($0) }
        inert.disconnect()
        inert.scheduleReconnect()
        inert.interruptSocketForReplacement()
        inert.connect()
        inert.forceReconnect(requestPeerRecovery: true)
        inert.wakeForRemoteNotification()
        XCTAssertFalse(inert.wantsConnection == false)
        XCTAssertTrue(inert.recoverPeerOnNextHello)
        XCTAssertFalse(edges.isEmpty)
        XCTAssertTrue(edges.allSatisfy { !$0 })
    }

    private func sessionPayload(
        type: String, sessionId: String, extra: [String: String]
    ) -> Data {
        var object = extra
        object["type"] = type
        object["sessionId"] = sessionId
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func pendingEntry(
        plain: Data, room: String = "room-a", expiresAt: TimeInterval? = nil,
        completion: ((Error?) -> Void)?
    ) -> RelayClient.PendingSessionPayload {
        let id = UUID()
        return RelayClient.PendingSessionPayload(
            id: id,
            queueKey: RelayClient.PendingSessionQueueKey(
                room: room, sessionId: "session-a", payload: .mcp("github")
            ),
            plain: plain, expiresAt: expiresAt ?? Date().timeIntervalSince1970 + 60,
            deliveryId: id.uuidString, completion: completion
        )
    }

    private func assertQueued(
        _ outcome: PendingSessionEnqueueOutcome, needsSubscription: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .queued(let actual) = outcome else {
            return XCTFail("Expected queued", file: file, line: line)
        }
        XCTAssertEqual(actual, needsSubscription, file: file, line: line)
    }

    private func assertRejected(
        _ outcome: PendingSessionEnqueueOutcome,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .rejected = outcome else {
            return XCTFail("Expected rejected", file: file, line: line)
        }
    }
}

import XCTest
@testable import GrantTap

extension SessionCatalogTests {
    func testGrokBuildIdentityNormalizesAndPresentsConsistently() {
        XCTAssertEqual(AgentIdentity.normalize("  Grok Build  "), "grok")
        XCTAssertEqual(AgentIdentity.displayName("grok"), "Grok Build")
        XCTAssertEqual(AgentIdentity.shortName("grok"), "Grok")
        XCTAssertEqual(AgentIdentity.glyph("grok"), "G")
    }

    func testGrokBuildExposesItsReportedTaskControls() {
        let support = ProviderControlSupport.forAgent("Grok Build")

        XCTAssertTrue(support.mcp)
        XCTAssertTrue(support.skills)
        XCTAssertTrue(support.cli)
    }

    func testCatalogCacheRoundTripsMaximumWireMetadataWithoutNarrowing() throws {
        let storage = FileManager.default.temporaryDirectory
            .appendingPathComponent("granttap-catalog-max-wire-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storage) }
        let maximumWireInteger = 9_007_199_254_740_991
        let session = SessionInfo(
            sessionId: "max-wire-cache",
            agent: "codex",
            state: "idle",
            startedAt: 1,
            lastActivityAt: 2,
            tokensSession: maximumWireInteger,
            tokensLastTurn: maximumWireInteger
        )

        SessionCatalogCache.save(
            sessions: [session],
            history: [],
            machine: "Mac",
            tokensRecent: maximumWireInteger,
            tokenWindowHours: maximumWireInteger,
            generatedAt: 3,
            storageDirectory: storage
        )
        let snapshot = try XCTUnwrap(
            SessionCatalogCache.load(storageDirectory: storage)
        )

        XCTAssertEqual(snapshot.tokensRecent, maximumWireInteger)
        XCTAssertEqual(snapshot.tokenWindowHours, maximumWireInteger)
        XCTAssertEqual(snapshot.sessions.map(\.sessionId), ["max-wire-cache"])
        XCTAssertEqual(snapshot.sessions.first?.tokensSession, maximumWireInteger)
    }

    func testMalformedSessionAndStatusNumbersFallbackWithoutHidingCatalogRows() throws {
        let malformedNumbers = [
            (name: "fractional", json: "1.5"),
            (name: "too-large", json: "9.23e18"),
            (name: "positive-infinity", json: "\"Infinity\""),
            (name: "negative-infinity", json: "\"-Infinity\""),
            (name: "nan", json: "\"NaN\""),
        ]
        for malformed in malformedNumbers {
            let decoder = JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(
                positiveInfinity: "Infinity",
                negativeInfinity: "-Infinity",
                nan: "NaN"
            )
            let data = Data("""
            {
              "type": "sessions.status",
              "machine": "Mac",
              "sessions": [
                {
                  "sessionId": "valid",
                  "agent": "codex",
                  "state": "idle",
                  "startedAt": 1,
                  "lastActivityAt": 2,
                  "tokensSession": 3,
                  "tokensLastTurn": 1
                },
                {
                  "sessionId": "malformed-\(malformed.name)",
                  "agent": "codex",
                  "state": "idle",
                  "startedAt": 1,
                  "lastActivityAt": 2,
                  "tokensSession": \(malformed.json),
                  "tokensLastTurn": \(malformed.json),
                  "contextTokensUsed": \(malformed.json),
                  "contextWindow": \(malformed.json),
                  "childThreads": [
                    {
                      "threadId": "bad-child",
                      "parentThreadId": "malformed-\(malformed.name)",
                      "depth": 1,
                      "state": "idle",
                      "startedAt": 1,
                      "lastActivityAt": 2,
                      "tokensSession": \(malformed.json),
                      "tokensLastTurn": \(malformed.json)
                    },
                    {
                      "threadId": "valid-child",
                      "parentThreadId": "malformed-\(malformed.name)",
                      "depth": 1,
                      "state": "idle",
                      "startedAt": 1,
                      "lastActivityAt": 2,
                      "tokensSession": 4,
                      "tokensLastTurn": 2
                    }
                  ]
                }
              ],
              "tokensRecent": \(malformed.json),
              "tokenWindowHours": \(malformed.json),
              "generatedAt": 3
            }
            """.utf8)

            let status = try decoder.decode(SessionsStatus.self, from: data)
            XCTAssertEqual(status.sessions.map(\.sessionId), [
                "valid", "malformed-\(malformed.name)",
            ])
            let session = try XCTUnwrap(status.sessions.last)
            XCTAssertEqual(session.tokensSession, 0)
            XCTAssertEqual(session.tokensLastTurn, 0)
            XCTAssertNil(session.contextTokensUsed)
            XCTAssertNil(session.contextWindow)
            XCTAssertEqual(session.childThreads?.map(\.threadId), ["valid-child"])
            XCTAssertEqual(status.tokensRecent, 0)
            XCTAssertEqual(status.tokenWindowHours, 12)
        }
    }

    func testMalformedSessionActivityMetricsFallbackWithoutDroppingRows() throws {
        let malformedNumbers = [
            (name: "negative", json: "-1"),
            (name: "fractional", json: "1.5"),
            (name: "too-large", json: "9.23e18"),
            (name: "positive-infinity", json: "\"Infinity\""),
            (name: "negative-infinity", json: "\"-Infinity\""),
            (name: "nan", json: "\"NaN\""),
        ]
        for malformed in malformedNumbers {
            let decoder = JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(
                positiveInfinity: "Infinity",
                negativeInfinity: "-Infinity",
                nan: "NaN"
            )
            let data = Data("""
            {
              "type": "session.activity",
              "sessionId": "root",
              "agent": "codex",
              "state": "idle",
              "entries": [
                {
                  "id": "malformed-\(malformed.name)",
                  "kind": "tool",
                  "text": "Malformed metrics stay optional",
                  "createdAt": 1,
                  "durationMs": \(malformed.json),
                  "estimatedContextTokens": \(malformed.json)
                },
                {
                  "id": "valid",
                  "kind": "tool",
                  "text": "Valid metrics survive",
                  "createdAt": 2,
                  "durationMs": 9007199254740991,
                  "estimatedContextTokens": 42
                }
              ],
              "generatedAt": 3
            }
            """.utf8)

            let activity = try decoder.decode(SessionActivity.self, from: data)
            XCTAssertEqual(activity.entries.map(\.id), ["malformed-\(malformed.name)", "valid"])
            XCTAssertNil(activity.entries[0].durationMs)
            XCTAssertNil(activity.entries[0].estimatedContextTokens)
            XCTAssertEqual(activity.entries[1].durationMs, 9_007_199_254_740_991)
            XCTAssertEqual(activity.entries[1].estimatedContextTokens, 42)
        }
    }

    func testPairingRelayValidationCoversPublicAndLocalNetworkBoundaries() {
        for local in [
            "localhost", "helper.localhost", "macbook.local", "macbook",
            "127.0.0.1", "10.0.0.8", "192.168.1.8", "172.16.0.8",
            "172.31.255.8", "[::1]:8787", "::1",
        ] {
            XCTAssertTrue(Pairing.isLocalNetworkHost(local), local)
        }
        for remote in [
            "example.com", "8.8.8.8", "172.32.0.1", "192.167.1.1",
            "[2001:db8::1]", "[broken",
        ] {
            XCTAssertFalse(Pairing.isLocalNetworkHost(remote), remote)
        }

        XCTAssertTrue(Pairing.isAllowedSocketRelay("wss://relay.granttap.app"))
        XCTAssertTrue(Pairing.isAllowedSocketRelay("ws://127.0.0.1:8787"))
        for rejected in [
            "ws://example.com", "https://relay.granttap.app", "wss://user@example.com",
            "wss://relay.granttap.app/path", "wss://relay.granttap.app?q=1", "not a url",
        ] {
            XCTAssertFalse(Pairing.isAllowedSocketRelay(rejected), rejected)
        }

        XCTAssertEqual(Pairing.normalizedPairingHTTPBase("relay.granttap.app"),
                       "https://relay.granttap.app")
        XCTAssertEqual(Pairing.normalizedPairingHTTPBase("macbook:8787"),
                       "http://macbook:8787")
        XCTAssertEqual(Pairing.normalizedPairingHTTPBase("wss://relay.granttap.app"),
                       "https://relay.granttap.app")
        XCTAssertEqual(Pairing.normalizedPairingHTTPBase("ws://localhost:8787"),
                       "http://localhost:8787")
        XCTAssertNil(Pairing.normalizedPairingHTTPBase("http://example.com"))
        XCTAssertNil(Pairing.normalizedPairingHTTPBase("ws://example.com"))
        XCTAssertNil(Pairing.normalizedPairingHTTPBase("ftp://localhost"))
        XCTAssertNil(Pairing.normalizedPairingHTTPBase(" "))
    }

    func testPairingShapeValidationRequiresCanonicalKeysAndBoundedMetadata() {
        let key = Data(repeating: 7, count: 32).base64EncodedString()
        XCTAssertTrue(Pairing.isValidKey(key))
        XCTAssertFalse(Pairing.isValidKey("not-base64"))
        XCTAssertFalse(Pairing.isValidKey(Data(repeating: 1, count: 31).base64EncodedString()))

        var pairing = Pairing(
            relayUrl: "wss://relay.granttap.app", room: String(repeating: "a", count: 32),
            role: "phone", deviceName: "Mac", senderId: "sender",
            myPublicKey: key, mySecretKey: key, peerPublicKey: key,
            pushAuth: String(repeating: "b", count: 64)
        )
        XCTAssertTrue(Pairing.isValid(pairing))
        XCTAssertTrue(Pairing.isValidPublic(pairing))
        pairing.role = "machine"
        XCTAssertFalse(Pairing.isValid(pairing))
        pairing.role = "phone"
        pairing.room = "NOT-HEX-UPPERCASE"
        XCTAssertFalse(Pairing.isValid(pairing))
        pairing.room = String(repeating: "a", count: 32)
        pairing.pushAuth = "short"
        XCTAssertFalse(Pairing.isValid(pairing))
        pairing.pushAuth = nil
        XCTAssertTrue(Pairing.isValid(pairing))
    }

    func testLenientWireDefaultsKeepBoundedRowsWhenOptionalFieldsAreHostile() throws {
        let activityJSON = #"{"sessionId":"session","entries":[7,{"kind":"message","text":" ","createdAt":"bad"},{"id":"tool","kind":"tool","text":"","createdAt":3,"durationMs":4.0,"estimatedContextTokens":-1,"outcome":"future","attachments":"bad"}],"generatedAt":"bad"}"#
        let activityData = Data(activityJSON.utf8)
        let activity = try JSONDecoder().decode(SessionActivity.self, from: activityData)
        XCTAssertEqual(activity.type, "session.activity")
        XCTAssertEqual(activity.agent, "codex")
        XCTAssertEqual(activity.state, "idle")
        XCTAssertEqual(activity.entries.map(\.id), ["tool"])
        XCTAssertEqual(activity.entries[0].durationMs, 4)
        XCTAssertNil(activity.entries[0].estimatedContextTokens)
        XCTAssertNil(activity.entries[0].outcome)
        XCTAssertNil(activity.entries[0].attachments)

        let statusJSON = #"{"sessions":"bad","history":[],"activities":"bad","tokensRecent":"12","tokenWindowHours":4.0}"#
        let status = try JSONDecoder().decode(SessionsStatus.self, from: Data(statusJSON.utf8))
        XCTAssertEqual(status.type, "sessions.status")
        XCTAssertTrue(status.machine.isEmpty)
        XCTAssertTrue(status.sessions.isEmpty)
        XCTAssertEqual(status.history, [])
        XCTAssertEqual(status.activities, [])
        XCTAssertEqual(status.tokensRecent, 12)
        XCTAssertEqual(status.tokenWindowHours, 4)

        let minimalJSON = #"{"sessionId":"minimal","lastActivityAt":"2026-08-23T10:00:00Z","tokensSession":"9","tokensLastTurn":2.0,"childThreads":"bad"}"#
        let minimal = try JSONDecoder().decode(SessionInfo.self, from: Data(minimalJSON.utf8))
        XCTAssertEqual(minimal.agent, "codex")
        XCTAssertEqual(minimal.state, "idle")
        XCTAssertEqual(minimal.startedAt, minimal.lastActivityAt)
        XCTAssertEqual(minimal.tokensSession, 9)
        XCTAssertEqual(minimal.tokensLastTurn, 2)
        XCTAssertNil(minimal.childThreads)
    }

}

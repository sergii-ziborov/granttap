import XCTest
import WatchConnectivity
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testActivityUsageNormalizesExplicitLegacyAndFallbackCapabilities() {
        let store = CapabilityUsageStore.shared
        store.clear()
        defer { store.clear() }
        let now = Date().timeIntervalSince1970 * 1_000
        let entries = [
            ActivityEntry(
                id: "multi", kind: "tool", text: "Multi", createdAt: now,
                capabilities: [
                    ObservedCapability(
                        kind: .mcp, name: "github", toolName: "search",
                        estimatedContextTokens: nil, estimatedBaselineTokens: 20,
                        durationMs: nil, outcome: nil, errorClass: nil,
                        resource: CapabilityResourceUsage(
                            attribution: .measured, cpuTimeMs: 24,
                            peakRssBytes: 112_000_000
                        )
                    ),
                    ObservedCapability(
                        kind: .skill, name: "review", toolName: "review",
                        estimatedContextTokens: 4, estimatedBaselineTokens: 10,
                        durationMs: 8, outcome: .success, errorClass: nil
                    ),
                ], durationMs: 12, outcome: .error, errorClass: "tool",
                estimatedContextTokens: 6
            ),
            ActivityEntry(id: "mcp", kind: "tool", text: "MCP", createdAt: now + 1,
                          toolName: "call", mcpServer: "figma"),
            ActivityEntry(id: "skill", kind: "tool", text: "Skill", createdAt: now + 2,
                          toolName: "skill", skill: "documents"),
            ActivityEntry(id: "shell", kind: "tool", text: "Run", createdAt: now + 3,
                          toolName: "provider.tools/exec_command"),
            ActivityEntry(id: "ignored", kind: "message", text: "Hi", createdAt: now + 4),
        ]
        let activity = SessionActivity(
            sessionId: "usage", agent: "codex", state: "working",
            entries: entries, generatedAt: now + 5
        )
        AppModel().recordCapabilityUsage(from: activity, sourceNamespace: "room")
        let events = store.events
        XCTAssertEqual(events.count, 5)
        XCTAssertTrue(events.contains { $0.sourceId == "room:multi:capability:0" })
        XCTAssertTrue(events.contains { $0.sourceId == "room:multi:capability:1" })
        XCTAssertEqual(events.first { $0.name == "github" }?.durationMs, 12)
        XCTAssertEqual(events.first { $0.name == "github" }?.outcome, .error)
        XCTAssertEqual(events.first { $0.name == "github" }?.estimatedContextTokens, 6)
        XCTAssertEqual(events.first { $0.name == "github" }?.resource?.cpuTimeMs, 24)
        XCTAssertTrue(events.contains { $0.kind == .cli && $0.name.contains("exec_command") })

        for name in ["bash", " Shell ", "provider:run_command", "a/b/terminal"] {
            XCTAssertTrue(AppModel.isLegacyShellToolName(name), name)
        }
        XCTAssertFalse(AppModel.isLegacyShellToolName("github.search"))
    }

    @MainActor
    func testAgentEventsCoverRoomCollisionDismissShellQuestionAndStatusClassification() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        let session = SessionInfo(
            sessionId: "session", agent: "claude", title: "Agent",
            state: "idle", startedAt: 1, lastActivityAt: 2,
            tokensSession: 0, tokensLastTurn: 0
        )
        model.sessions = [session]
        model.requestSourceRoom["collision"] = "room-a"
        model.receive(event(
            text: "Ignored", id: "collision", kind: "question", sessionId: nil,
            createdAt: now
        ), fromRoom: "room-b")
        XCTAssertTrue(model.log.first?.contains("collision") == true)

        model.receive(event(
            text: " dismiss ", id: "dismiss", kind: "status", sessionId: "session",
            createdAt: now + 1
        ))
        XCTAssertTrue(model.log.first?.contains("legacy dismiss") == true)

        model.receive(event(
            text: "Allow Cursor shell command?", id: "shell", kind: "question",
            sessionId: "session", createdAt: now + 2
        ))
        XCTAssertEqual(model.pending.first?.tool, "Shell")

        model.receive(event(
            text: "Which option?", id: "question", kind: "question",
            sessionId: "session", createdAt: now + 3
        ))
        XCTAssertTrue(model.questions.contains { $0.requestId == "question" })

        for (index, text) in [
            "Provider not logged in", "Quota reached", "Out of tokens", "CLI not found",
        ].enumerated() {
            model.receive(event(
                text: text, id: nil, kind: "response", sessionId: "session",
                createdAt: now + Double(100 + index)
            ))
        }
        let statusTexts = model.activities["session"]?.entries
            .filter { $0.kind == "status" }.map(\.text) ?? []
        XCTAssertEqual(statusTexts.count, 4)
        XCTAssertEqual(
            AppModel.agentEventEntryId(text: "stable", createdAt: 1),
            AppModel.agentEventEntryId(text: "stable", createdAt: 1)
        )
    }

    @MainActor
    func testPushToWatchBuildsEveryProjectionAndSecondaryRoomConsumesOrigin() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            ConnectionRegistryLogic.upsert(
                .empty, pairing: testPairing(room: "room-a"), prefer: true
            ), pairing: testPairing(room: "room-b"), prefer: false
        )
        var delivery = existingSessionDelivery(
            createdAt: now, id: "secondary", sessionId: "local"
        )
        delivery.roomId = "room-b"
        model.deliveries = [delivery]
        model.localOnlySessionIds = ["local"]
        model.receive(event(
            text: "Finished", id: nil, kind: "response", sessionId: "native",
            originMessageId: delivery.id, createdAt: now
        ), fromRoom: "room-b")
        XCTAssertTrue(model.deliveries.isEmpty)

        model.sessions = [SessionInfo(
            sessionId: "watch", agent: "codex", title: "Watch", state: "working",
            startedAt: 1, lastActivityAt: 2, tokensSession: 3, tokensLastTurn: 1
        )]
        model.pending = [ApprovalRequest(
            type: "approval.request", requestId: "watch-approval", agent: "codex",
            kind: "permission", tool: "Bash", title: "Run?", command: "npm test",
            cwd: "/repo", sessionId: "watch", risk: .medium,
            danger: .caution, createdAt: 1
        )]
        model.questions = [event(
            text: "Question?", id: "watch-question", kind: "question", sessionId: "watch"
        )]
        model.activities["watch"] = SessionActivity(
            sessionId: "watch", agent: "codex", state: "working",
            entries: [ActivityEntry(id: "one", kind: "message", text: "Hi", createdAt: 1)],
            generatedAt: 1
        )
        model.agentIntegrations = [AgentIntegrationInfo(
            agent: "codex", installed: true, hookConfigured: true
        )]
        model.pushToWatch(force: true)
    }

    @MainActor
    func testWatchBridgeStartsDeduplicatesRetriesAndHandlesLifecycle() async {
        let model = AppModel()
        let transport = WatchSessionTransportSpy()
        let bridge = WatchBridge(transport: transport, model: model)
        bridge.start()
        XCTAssertTrue(transport.delegate === bridge)
        XCTAssertEqual(transport.activationCount, 1)

        let first = WatchState(machine: "Mac", connected: true)
        bridge.push(first)
        XCTAssertTrue(transport.contexts.isEmpty)
        transport.activationState = .activated
        bridge.push(first)
        bridge.push(first)
        XCTAssertEqual(transport.contexts.count, 1)

        transport.error = WatchSessionTransportError.rejected
        bridge.push(WatchState(machine: "Air", connected: true))
        XCTAssertEqual(transport.contexts.count, 2)
        transport.error = nil
        bridge.push(WatchState(machine: "Air", connected: true))
        XCTAssertEqual(transport.contexts.count, 3)

        bridge.session(WCSession.default, activationDidCompleteWith: .activated, error: nil)
        bridge.sessionDidBecomeInactive(WCSession.default)
        bridge.sessionDidDeactivate(WCSession.default)
        await Task.yield()
        XCTAssertGreaterThanOrEqual(transport.activationCount, 2)

        WatchBridge(transport: nil, model: model).start()
        WatchBridge(transport: nil, model: model).push(first)
    }

    @MainActor
    func testWatchBridgeDecodesEveryActionAndRepliesToWatch() async throws {
        let model = AppModel()
        let transport = WatchSessionTransportSpy()
        transport.activationState = .activated
        let bridge = WatchBridge(transport: transport, model: model)
        let session = WCSession.default
        bridge.session(session, didReceiveMessage: ["action": Data("bad".utf8)])

        bridge.session(session, didReceiveMessage: try actionMessage(
            .decision("decision", "allow", sessionId: "task")
        ))
        bridge.session(session, didReceiveUserInfo: try actionMessage(
            .newTask("Build it", agent: "codex")
        ))
        bridge.session(session, didReceiveUserInfo: try actionMessage(
            .message("", sessionId: nil)
        ))
        bridge.session(session, didReceiveUserInfo: try actionMessage(
            .subscription("task", active: true, source: String(repeating: "s", count: 40))
        ))
        bridge.session(session, didReceiveUserInfo: try actionMessage(.refresh()))

        var reply: [String: Any] = [:]
        bridge.session(session, didReceiveMessage: try actionMessage(
            .subscription("task", active: false, source: String(repeating: "s", count: 40))
        )) { reply = $0 }
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(reply["ok"] as? Bool, true)
        XCTAssertTrue(model.deliveries.contains { $0.text == "Build it" })
        XCTAssertNil(model.activitySubscribers["task"])
    }

    private func actionMessage(_ action: WatchAction) throws -> [String: Any] {
        ["action": try JSONEncoder().encode(action)]
    }

    private func event(
        text: String, id: String?, kind: String?, sessionId: String?,
        originMessageId: String? = nil, createdAt: Double = 1
    ) -> AgentEvent {
        AgentEvent(
            type: "agent.event", text: text, requestId: id, kind: kind,
            sessionId: sessionId, originMessageId: originMessageId, createdAt: createdAt
        )
    }
}

private enum WatchSessionTransportError: Error { case rejected }

private final class WatchSessionTransportSpy: WatchSessionTransport {
    var activationState: WCSessionActivationState = .notActivated
    var activationCount = 0
    var contexts: [[String: Any]] = []
    var error: Error?
    weak var delegate: WCSessionDelegate?

    func install(delegate: WCSessionDelegate) { self.delegate = delegate }
    func activate() { activationCount += 1 }
    func updateApplicationContext(_ context: [String: Any]) throws {
        contexts.append(context)
        if let error { throw error }
    }
}

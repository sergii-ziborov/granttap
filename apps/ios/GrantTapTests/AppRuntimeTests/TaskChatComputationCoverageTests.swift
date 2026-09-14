import XCTest
import SwiftUI
import UIKit
@testable import GrantTap

extension AppRuntimeTests {
    @MainActor
    func testTaskChatComputesRoutesUsageCapabilitiesAndBindings() {
        let model = AppModel()
        let room = "chat-compute-room"
        let client = RelayClient(pairing: testPairing(room: room))
        var registry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: room)
        )
        registry = ConnectionRegistryLogic.noteCatalog(
            registry, roomId: room,
            generatedAt: Date().timeIntervalSince1970 * 1_000, machineName: "Review Mac"
        )
        model.connectionRegistry = registry
        model.roomRuntime[room] = AppModel.RoomRuntime(socketUp: true)
        model.relaysByRoom[room] = client
        var session = chatCoverageSession(id: "chat-compute")
        model.sessions = [session]
        model.rememberSessionSourceRoom(room, sessionId: session.sessionId)
        model.activities[session.sessionId] = SessionActivity(
            sessionId: session.sessionId, agent: session.agent, state: "working",
            entries: [
                ActivityEntry(id: "root", kind: "message", text: "Root", createdAt: 1),
                ActivityEntry(
                    id: "child", kind: "message", text: "Child", createdAt: 2,
                    childThreadId: "child-thread"
                ),
            ], generatedAt: 2
        )
        CapabilityUsageStore.shared.clear()
        defer { CapabilityUsageStore.shared.clear() }
        let now = Date().timeIntervalSince1970 * 1_000 + 1_000
        CapabilityUsageStore.shared.record(
            .cli, name: "Bash", sessionId: session.sessionId, sourceId: "one",
            createdAt: now, commandPreview: "npm test", estimatedContextTokens: 20,
            sourceNamespace: room
        )
        CapabilityUsageStore.shared.record(
            .mcp, name: "github", sessionId: session.sessionId, sourceId: "two",
            createdAt: now + 1, estimatedContextTokens: 30, sourceNamespace: room
        )

        let chat = TaskChatView(session: session, modelOverride: model)
        XCTAssertEqual(chat.chatSessionId, session.sessionId)
        XCTAssertEqual(chat.currentSession.sessionId, session.sessionId)
        XCTAssertEqual(chat.entries.count, 2)
        XCTAssertEqual(chat.rootEntries.map(\.id), ["root"])
        XCTAssertTrue(chat.activitySnapshotKnown)
        XCTAssertTrue(chat.liveStamp.contains("-2-"))
        XCTAssertEqual(chat.contextPercent, 90)
        XCTAssertEqual(chat.chatShellRows.first?.calls, 1)
        XCTAssertEqual(chat.capabilityUsageSummary(.mcp, name: "github"), "1× · ≈ 30 context")
        XCTAssertNil(chat.capabilityUsageSummary(.skill, name: "missing"))
        XCTAssertEqual(chat.capabilityRows.count, 3)
        XCTAssertNil(chat.chatSendAvailability)

        chat.chatModelBinding.wrappedValue = .opus
        chat.chatPermissionBinding.wrappedValue = .bypassPermissions
        XCTAssertEqual(chat.chatModelBinding.wrappedValue, .opus)
        XCTAssertEqual(chat.chatPermissionBinding.wrappedValue, .bypassPermissions)
        if let mcp = chat.capabilityRows.first(where: { $0.kind == .mcp }) {
            chat.toggleCapability(mcp)
        }
        if let skill = chat.capabilityRows.first(where: { $0.kind == .skill }) {
            chat.toggleCapability(skill)
        }
        if let cli = chat.capabilityRows.first(where: { $0.kind == .cli }) {
            chat.toggleCapability(cli)
        }
        session = model.sessions[0]
        XCTAssertFalse(session.mcpServers?.first?.allowed == true)
        XCTAssertFalse(session.skills?.first?.allowed == true)
        XCTAssertFalse(session.shellAllowed == true)

        let voice = Dictator(accessOverride: { $0(true) }, sessionStartOverride: {})
        voice.isRecording = true
        voice.transcript = "Continue by voice"
        voice.detectedLanguage = "EN"
        voice.errorText = "Speech warning"
        let attachment = AttachmentDraft(
            name: "note.txt", mimeType: "text/plain", data: Data("note".utf8)
        )
        let rich = TaskChatView(
            session: session, modelOverride: model, initialDraft: "Continue",
            initialAttachments: [attachment], initialSelectedMcp: "github",
            initialSelectedSkill: "documents", initialAttachmentError: "Attachment warning",
            initialShowCapabilities: true, dictator: voice
        )
        assertRendered(rich.environmentObject(model))
        if let row = rich.childThreads.first {
            let childEntries = rich.entries.filter { $0.childThreadId == row.thread.threadId }
            assertRendered(AgentThreadTranscript(
                row: row, entries: childEntries, accent: rich.accent,
                servers: session.mcpServers ?? [], expanded: true
            ).environmentObject(model))
            assertRendered(AgentThreadTranscript(
                row: row, entries: [], accent: rich.accent,
                servers: [], expanded: true
            ).environmentObject(model))
        }
    }

    @MainActor
    func testTaskChatSendCoversEmptyReplyBlockedInvalidAndSuccessfulPaths() {
        let model = AppModel()
        model.deliveries = []
        let session = chatCoverageSession(id: "chat-send")
        model.sessions = [session]
        TaskChatView(session: session, modelOverride: model).send()
        XCTAssertTrue(model.deliveries.isEmpty)

        TaskChatView(
            session: session, modelOverride: model,
            initialDraft: " ", initialReplyRequestId: "reply"
        ).send()
        XCTAssertTrue(model.deliveries.isEmpty)
        model.questions = [AgentEvent(
            type: "agent.event", text: "What next?", requestId: "reply",
            kind: "question", sessionId: session.sessionId, createdAt: 1
        )]
        TaskChatView(
            session: session, modelOverride: model,
            initialDraft: "Continue", initialReplyRequestId: "reply"
        ).send()
        XCTAssertEqual(model.deliveries.first?.requestId, "reply")

        model.deliveries = []
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            ConnectionRegistryLogic.upsert(.empty, pairing: testPairing(room: "one")),
            pairing: testPairing(room: "two"), prefer: false
        )
        TaskChatView(
            session: session, modelOverride: model, initialDraft: "Blocked"
        ).send()
        XCTAssertTrue(model.deliveries.isEmpty)

        let room = "send-room"
        var registry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: room)
        )
        registry = ConnectionRegistryLogic.noteCatalog(
            registry, roomId: room,
            generatedAt: Date().timeIntervalSince1970 * 1_000, machineName: "Mac"
        )
        model.connectionRegistry = registry
        model.roomRuntime[room] = AppModel.RoomRuntime(socketUp: true)
        model.rememberSessionSourceRoom(room, sessionId: session.sessionId)
        let invalid = Array(repeating: AttachmentDraft(
            name: "a", mimeType: "text/plain", data: Data("x".utf8)
        ), count: AttachmentDraft.maxCount + 1)
        TaskChatView(
            session: session, modelOverride: model,
            initialDraft: "Invalid", initialAttachments: invalid
        ).send()
        XCTAssertTrue(model.deliveries.isEmpty)

        let attachment = AttachmentDraft(
            name: "a.txt", mimeType: "text/plain", data: Data("hello".utf8)
        )
        TaskChatView(
            session: session, modelOverride: model, initialDraft: "Ship it",
            initialAttachments: [attachment], initialSelectedMcp: "github",
            initialSelectedSkill: "documents"
        ).send()
        XCTAssertEqual(model.deliveries.first?.text, "Ship it")
        XCTAssertEqual(model.deliveries.first?.preferredMcp, "github")
        XCTAssertEqual(model.deliveries.first?.skill, "documents")
    }

    @MainActor
    func testTaskChatRendersConnectionEmptyTimeoutAndMeshTimelineStates() {
        let model = AppModel()
        let plain = chatCoverageSession(id: "chat-states")
        model.sessions = [plain]
        assertRendered(TaskChatView(session: plain, modelOverride: model).environmentObject(model))

        let room = "chat-states-room"
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: testPairing(room: room)
        )
        model.roomRuntime[room] = AppModel.RoomRuntime(socketUp: true)
        model.rememberSessionSourceRoom(room, sessionId: plain.sessionId)
        model.activities[plain.sessionId] = SessionActivity(
            sessionId: plain.sessionId, agent: plain.agent, state: "working",
            entries: [], generatedAt: 3
        )
        assertRendered(TaskChatView(
            session: plain, modelOverride: model, initialLoadTimedOut: true
        ).environmentObject(model))

        let meshSession = SessionInfo(
            sessionId: "mesh-chat", agent: "claude", projectId: "project", taskId: "task",
            title: "Mesh chat", state: "working", startedAt: 1, lastActivityAt: 2,
            tokensSession: 0, tokensLastTurn: 0
        )
        model.sessions = [meshSession]
        model.meshSnapshots = ["project": ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [
                .init(taskId: "task", projectId: "project", title: "Mesh chat", goal: "Ship",
                      state: "working", ownerSessionId: "mesh-chat", createdAt: 1, updatedAt: 2),
                .init(taskId: "qa", projectId: "project", title: "QA", goal: "Verify",
                      state: "planned", createdAt: 1, updatedAt: 1),
            ], executions: [], claims: [], dependencies: [], events: [
                .init(type: "mesh.event", sessionId: "task", eventId: "progress",
                      projectId: "project", taskId: "task", sourceSessionId: "mesh-chat",
                      eventType: "TASK_PROGRESS", createdAt: 2,
                      payload: .init(summary: "Implementation ready")),
            ], generatedAt: 3
        )]
        assertRendered(TaskChatView(
            session: meshSession, modelOverride: model
        ).environmentObject(model))
    }

    private func chatCoverageSession(id: String) -> SessionInfo {
        SessionInfo(
            sessionId: id, agent: "codex", title: "Coverage chat", cwd: "/repo",
            model: "gpt", state: "working", startedAt: 1, lastActivityAt: 2,
            tokensSession: 100, tokensLastTurn: 10,
            contextTokensUsed: 90, contextWindow: 100,
            mcpServers: [McpServerInfo(
                name: "github", configuredEnabled: true, allowed: true
            )],
            skills: [SkillInfo(name: "documents", allowed: true)],
            childThreads: [ChildThreadInfo(
                threadId: "child-thread", parentThreadId: id, title: "Child",
                depth: 1, state: "working", startedAt: 1, lastActivityAt: 2,
                tokensSession: 1, tokensLastTurn: 1
            )], shellAllowed: true
        )
    }

    @MainActor
    private func assertRendered<V: View>(_ view: V) {
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        XCTAssertNotNil(controller.view.window)
        window.isHidden = true
    }
}

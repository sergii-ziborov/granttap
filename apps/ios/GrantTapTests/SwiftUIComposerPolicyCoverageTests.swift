import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class SwiftUIComposerPolicyCoverageTests: XCTestCase {
    func testRoutePickerRendersLazyOptionsAndComputesCatalogCounts() {
        let catalog = CapabilityCatalogStore()
        catalog.apply(CapabilityCatalogStatus(
            type: "capabilities.status", computerId: "ignored", machine: "Mac",
            entries: [
                CapabilityCatalogEntry(
                    provider: "codex", workspace: "/repo", kind: .mcp,
                    name: "github", available: true, allowed: true
                ),
                CapabilityCatalogEntry(
                    provider: "codex", workspace: nil, kind: .mcp,
                    name: "hidden", available: false, allowed: true
                ),
            ], generatedAt: 1
        ), fromRoom: "room")
        let picker = TaskComposerRoutePicker(
            provider: .constant("codex"), computerId: .constant("room"),
            workspace: .constant("/repo"),
            computers: [
                TaskComposerComputerOption(id: "room", name: "Mac", phase: .live),
                TaskComposerComputerOption(id: "offline", name: "Air", phase: .phoneOffline),
            ], workspaces: ["/repo", "/tmp/sample"], catalog: catalog
        )

        XCTAssertEqual(picker.selectedComputer?.id, "room")
        XCTAssertEqual(picker.workspaceName("/tmp/sample"), "sample")
        XCTAssertEqual(picker.mcpCount(for: "codex"), 1)
        assertRendered(VStack {
            picker
            picker.providerOptions
            picker.computerOptions
            picker.routeLabel(icon: AnyView(Image(systemName: "folder")),
                              value: String(repeating: "x", count: 30), accessibility: "folder")
            picker.availabilityDot(.live)
            picker.availabilityDot(.transitional)
            picker.availabilityDot(.offline)
        })

        let empty = TaskComposerRoutePicker(
            provider: .constant("claude"), computerId: .constant(nil),
            workspace: .constant(""), computers: [], workspaces: [], catalog: catalog
        )
        XCTAssertNil(empty.selectedComputer)
        assertRendered(VStack { empty; empty.providerOptions })
    }

    func testGlobalCapabilityPolicyRendersRowsAndExecutesEveryPolicyKind() throws {
        let model = AppModel()
        let room = "policy-room"
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: policyPairing(room: room)
        )
        let catalog = CapabilityCatalogStore()
        catalog.apply(CapabilityCatalogStatus(
            type: "capabilities.status", computerId: "ignored", machine: "Reported Mac",
            entries: [
                CapabilityCatalogEntry(
                    provider: "codex", workspace: "/repo", kind: .mcp,
                    name: "github", available: true, allowed: true
                ),
                CapabilityCatalogEntry(
                    provider: "claude", workspace: nil, kind: .skill,
                    name: "review", available: true, allowed: false
                ),
            ], generatedAt: 1
        ), fromRoom: room)

        let mcp = GlobalCapabilityPolicySection(kind: .mcp, model: model, catalog: catalog)
        let skill = GlobalCapabilityPolicySection(kind: .skill, model: model, catalog: catalog)
        let cli = GlobalCapabilityPolicySection(kind: .cli, model: model, catalog: catalog)
        let row = try XCTUnwrap(mcp.rows.first)
        XCTAssertEqual(mcp.computerName(row), "Policy Mac")
        XCTAssertTrue(mcp.metadata(row).contains("repo"))
        mcp.setAllowed(false, row: row)
        skill.setAllowed(true, row: try XCTUnwrap(skill.rows.first))
        cli.setAllowed(false, row: row)
        assertRendered(List { mcp; skill; cli })

        let empty = CapabilityCatalogStore()
        assertRendered(List {
            GlobalCapabilityPolicySection(kind: .mcp, model: model, catalog: empty)
            GlobalCapabilityPolicySection(kind: .skill, model: model, catalog: empty)
        })
    }

    func testSubscriptionRendersEveryEntitlementAndAvailabilityState() {
        let future = Date().addingTimeInterval(86_400)
        let states: [SubscriptionAccessState] = [
            .trial(expiresAt: future), .active(expiresAt: future), .active(expiresAt: nil),
            .gracePeriod(expiresAt: future), .billingRetry(expiresAt: future),
            .expired, .revoked, .unavailable,
        ]
        let availability: [SubscriptionStore.Availability] = [
            .loading, .notConfigured, .failed("Store offline"), .ready,
        ]
        assertRendered(VStack {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                SubscriptionView(store: self.subscriptionStore(state: state)).statusRow
            }
            ForEach(Array(availability.enumerated()), id: \.offset) { _, state in
                SubscriptionView(store: SubscriptionStore(
                    startObserving: false, availability: state
                )).unavailableRow
            }
        })
        let errorStore = SubscriptionStore(
            startObserving: false, availability: .failed("Offline"), lastError: "Retry"
        )
        errorStore.clearError()
        XCTAssertNil(errorStore.lastError)
    }

    func testContentComposerComputesRoutesAndCoversSendBranches() throws {
        let model = AppModel()
        model.deliveries = []
        let room = "compose-room"
        var registry = ConnectionRegistryLogic.upsert(
            .empty, pairing: policyPairing(room: room)
        )
        let now = Date().timeIntervalSince1970 * 1_000
        registry = ConnectionRegistryLogic.noteCatalog(
            registry, roomId: room, generatedAt: now, machineName: "Compose Mac"
        )
        model.connectionRegistry = registry
        model.roomRuntime[room] = AppModel.RoomRuntime(socketUp: true, socketUpSince: now)

        let empty = ContentView(modelOverride: model)
        empty.send()
        XCTAssertTrue(model.deliveries.isEmpty)
        XCTAssertEqual(empty.newTaskRouteLabel, "Codex · Policy Mac")
        XCTAssertEqual(empty.taskComposerComputers.first?.name, "Compose Mac")

        let invalid = Array(repeating: AttachmentDraft(
            name: "a", mimeType: "text/plain", data: Data("x".utf8)
        ), count: AttachmentDraft.maxCount + 1)
        ContentView(
            messageText: "Invalid", attachments: invalid, composeRoomId: room,
            modelOverride: model
        ).send()
        XCTAssertTrue(model.deliveries.isEmpty)

        ContentView(
            messageText: "Create tests", composeAgent: "claude",
            newTaskCwd: "/repo", composeRoomId: room, modelOverride: model
        ).send()
        XCTAssertEqual(model.deliveries.first?.text, "Create tests")
        XCTAssertEqual(model.deliveries.first?.cwd, "/repo")

        model.deliveries = []
        let session = SessionInfo(
            sessionId: "existing", agent: "codex", title: "Existing", cwd: "/repo",
            state: "idle", startedAt: 1, lastActivityAt: 2,
            tokensSession: 0, tokensLastTurn: 0
        )
        model.sessions = [session]
        model.rememberSessionSourceRoom(room, sessionId: session.sessionId)
        ContentView(
            composeSessionId: session.sessionId, messageText: "Continue",
            modelOverride: model
        ).send()
        XCTAssertEqual(model.deliveries.first?.sessionId, session.sessionId)

        model.deliveries = []
        model.questions = [AgentEvent(
            type: "agent.event", text: "Next?", requestId: "question",
            kind: "question", sessionId: session.sessionId, createdAt: 1
        )]
        ContentView(
            composeSessionId: session.sessionId, messageText: "Reply",
            replyRequestId: "question", modelOverride: model
        ).send()
        XCTAssertEqual(model.deliveries.first?.requestId, "question")

        let attachment = AttachmentDraft(
            name: "note.txt", mimeType: "text/plain", data: Data("note".utf8)
        )
        let dictator = Dictator(
            accessOverride: { $0(true) }, sessionStartOverride: {}
        )
        dictator.isStarting = true
        dictator.detectedLanguage = "EN"
        dictator.errorText = "Microphone unavailable"
        assertRendered(ContentView(
            showNewTask: true, showNewTaskRoute: true, messageText: "Build",
            attachments: [attachment], attachmentError: "Attachment warning",
            composeAgent: "claude", composeRoomId: room, modelOverride: model,
            dictator: dictator
        ).environmentObject(model))

        dictator.isStarting = false
        dictator.isRecording = true
        dictator.transcript = "Continue from voice"
        assertRendered(ContentView(
            showNewTask: true,
            composeSessionId: session.sessionId, messageText: "Continue",
            attachments: [attachment], modelOverride: model, dictator: dictator
        ).environmentObject(model))
    }

    func testTaskAndLegacyComposersRenderRouteStatesAndSendAttachments() {
        let model = AppModel()
        model.deliveries = []
        let session = SessionInfo(
            sessionId: "composer", agent: "cursor", title: "Composer", cwd: "/repo",
            model: "cursor", state: "working", startedAt: 1, lastActivityAt: 2,
            tokensSession: 1, tokensLastTurn: 1,
            contextTokensUsed: 90, contextWindow: 100
        )
        model.sessions = [session]
        let attachment = AttachmentDraft(
            name: "note.txt", mimeType: "text/plain", data: Data("note".utf8)
        )
        let voice = Dictator(accessOverride: { $0(true) }, sessionStartOverride: {})
        voice.isStarting = true
        voice.errorText = "Speech warning"
        let chat = TaskChatView(
            session: session, modelOverride: model, initialDraft: "Continue",
            initialAttachments: [attachment], initialSelectedMcp: "github",
            initialSelectedSkill: "review", initialAttachmentError: "Attachment warning",
            dictator: voice
        )
        XCTAssertTrue(chat.chatSendAvailability?.blocksSending == true)
        assertRendered(chat.environmentObject(model))

        SessionComposerBar(
            sessionId: session.sessionId, agent: "codex", mcpServers: [], skills: [],
            accent: Theme.codex, modelOverride: model
        ).send()
        XCTAssertTrue(model.deliveries.isEmpty)
        let invalid = Array(repeating: attachment, count: AttachmentDraft.maxCount + 1)
        SessionComposerBar(
            sessionId: session.sessionId, agent: "codex", mcpServers: [], skills: [],
            accent: Theme.codex, modelOverride: model,
            initialDraft: "Invalid", initialAttachments: invalid
        ).send()
        XCTAssertTrue(model.deliveries.isEmpty)
        SessionComposerBar(
            sessionId: session.sessionId, agent: "codex", mcpServers: [], skills: [],
            accent: Theme.codex, modelOverride: model, initialDraft: "Send",
            initialAttachments: [attachment], initialSelectedMcp: "github",
            initialSelectedSkill: "review"
        ).send()
        XCTAssertEqual(model.deliveries.first?.preferredMcp, "github")
        XCTAssertEqual(model.deliveries.first?.skill, "review")
        assertRendered(SessionComposerBar(
            sessionId: session.sessionId, agent: "claude",
            mcpServers: [McpServerInfo(
                name: "github", configuredEnabled: true, allowed: true
            )], skills: [SkillInfo(name: "review", allowed: true)],
            accent: Theme.claude, modelOverride: model, initialDraft: "Continue",
            initialAttachments: [attachment], initialAttachmentError: "Attachment warning",
            dictator: voice
        ).environmentObject(model))
    }

    private func subscriptionStore(state: SubscriptionAccessState) -> SubscriptionStore {
        SubscriptionStore(
            startObserving: false,
            entitlement: SubscriptionEntitlement(
                state: state, product: .personal, seatLimit: SubscriptionProduct.personal.seatLimit
            ), availability: .notConfigured
        )
    }

    private func policyPairing(room: String) -> Pairing {
        Pairing(
            relayUrl: "ws://127.0.0.1:1", room: room, role: "phone",
            deviceName: "Policy Mac", senderId: "policy",
            myPublicKey: "public", mySecretKey: "secret", peerPublicKey: "peer"
        )
    }

    private func assertRendered<V: View>(
        _ view: V, file: StaticString = #filePath, line: UInt = #line
    ) {
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        let image = UIGraphicsImageRenderer(size: frame.size).image { _ in
            controller.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 2_000, file: file, line: line)
        window.isHidden = true
    }
}

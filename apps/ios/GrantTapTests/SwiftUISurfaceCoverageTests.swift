import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class SwiftUISurfaceCoverageTests: XCTestCase {
    private var model: AppModel!

    override func setUp() async throws {
        model = AppModel.shared
        model.startDemo()
    }

    override func tearDown() async throws {
        model.stopDemo()
        model = nil
    }

    func testProjectSectionDestinationsRender() throws {
        let snapshot = try XCTUnwrap(model.meshSnapshots.values.first)
        assertRendered(List { ProjectDestinationRows(snapshot: snapshot, model: model) })
        assertRendered(ProjectKnowledgeView(snapshot: snapshot, model: model))
        assertRendered(ProjectToolsSkillsView(snapshot: snapshot, model: model))
        assertRendered(ProjectWriteToAgentsSheet(snapshot: snapshot, model: model))
        assertRendered(ProjectMeshView(snapshot: snapshot, model: model))
    }

    func testHistoryAndUsageDestinationsRender() throws {
        let historical = try XCTUnwrap(model.sessionHistory.first)
        assertRendered(ChatHistorySheet().environmentObject(model))
        assertRendered(HistoricalChatDetail(session: historical).environmentObject(model))
        assertRendered(CapabilityUsageHistoryView(
            kind: .mcp, name: "github", agent: "codex", modelName: "gpt-5.6-sol"
        ))
        assertRendered(CapabilityUsageHistoryView(
            kind: .cli, name: "rg", agent: "codex", modelName: nil
        ))
    }

    func testSettingsDestinationsRender() {
        assertRendered(AboutGrantTapView())
        assertRendered(ConnectionDetailSheet().environmentObject(model))
        assertRendered(SubscriptionView())
        assertRendered(NavigationView { AuditLogView() })
        assertRendered(List {
            GlobalCapabilityPolicySection(kind: .mcp)
            GlobalCapabilityPolicySection(kind: .skill)
            GlobalCapabilityPolicySection(kind: .cli)
        })
    }

    func testTaskControlsAndLegacyComposerRender() throws {
        let session = try XCTUnwrap(model.sessions.first)
        let rows = [
            ChatCapabilityRow(kind: .mcp, name: "github", allowed: true,
                              calls: 4, tokens: 320, needsAuth: false),
            ChatCapabilityRow(kind: .skill, name: "ios-qa", allowed: nil,
                              calls: 1, tokens: 90, needsAuth: false),
            ChatCapabilityRow(kind: .cli, name: "Bash", allowed: false,
                              calls: 2, tokens: 180, needsAuth: false),
        ]
        assertRendered(ChatCapabilitySheet(
            sessionId: session.sessionId, session: session, rows: rows,
            accent: Theme.codex, onToggle: { _ in }
        ).environmentObject(model))
        assertRendered(SessionComposerBar(
            sessionId: session.sessionId, agent: session.agent,
            mcpServers: session.mcpServers ?? [], skills: session.skills ?? [],
            accent: Theme.codex
        ).environmentObject(model))
    }

    func testActivityAndAttachmentVariantsRender() {
        let now = Date().timeIntervalSince1970 * 1_000
        let entries = [
            ActivityEntry(id: "mcp", kind: "tool", text: "Search issues", createdAt: now,
                          mcpServer: "github", estimatedContextTokens: 75),
            ActivityEntry(id: "skill", kind: "tool", text: "Review document", createdAt: now,
                          skill: "documents"),
            ActivityEntry(id: "user", kind: "user", text: "Continue", createdAt: now,
                          attachments: ["notes.txt"]),
            ActivityEntry(id: "status", kind: "status", text: "Working", createdAt: now),
        ]
        assertRendered(ScrollView {
            VStack {
                ForEach(entries) { entry in
                    ActivityRow(entry: entry, accent: Theme.codex, compact: false)
                        .environmentObject(self.model)
                }
                SurfaceBindingHost().environmentObject(self.model)
            }
            .padding()
        })
    }

    func testImageAndSecurityChromeRender() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 160)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
        }
        assertRendered(ImagePreviewScreen(image: image, onClose: {}))
        assertRendered(SecurityPrivacyShield())
        assertRendered(GrantTapLaunchChrome())
        assertRendered(SecurityLockView(security: .shared, pendingCount: 2))
        XCTAssertEqual(GrantTapBrandMark.assetName, "BrandMark")
    }

    func testPinAndProviderControlSurfacesRenderAllPrimaryVariants() {
        assertRendered(PinPadView(
            title: "Enter PIN", subtitle: "Four digits",
            onCancel: {}, onComplete: { $0 == "1234" }
        ))
        assertRendered(PinDots(filled: 0))
        assertRendered(PinDots(filled: AppPinStore.length))
        assertRendered(PinKeypad(onDigit: { _ in }, onDelete: {}))
        assertRendered(PinKeypad(
            onDigit: { _ in }, onDelete: {}, biometryName: "Face ID",
            onBiometry: {}
        ))
        XCTAssertGreaterThanOrEqual(PinKeypad.keyHeight, 64)
        XCTAssertGreaterThanOrEqual(PinKeypad.keySpacing, 10)
        assertRendered(InlinePinPad(onComplete: { $0 == "123456" }))
        _ = ShakeEffect(animatableData: 1).effectValue(size: CGSize(width: 40, height: 40))
    }

    func testConnectionAndExactCapabilityChatDestinationsRender() throws {
        let originalRegistry = model.connectionRegistry
        let originalRuntime = model.roomRuntime
        let originalSources = model.sessionSourceRooms
        defer {
            model.connectionRegistry = originalRegistry
            model.roomRuntime = originalRuntime
            model.sessionSourceRooms = originalSources
        }
        let room = "surface-room"
        var registry = ConnectionRegistryLogic.upsert(
            .empty, pairing: surfacePairing(room: room), prefer: true
        )
        let now = Date().timeIntervalSince1970 * 1_000
        registry = ConnectionRegistryLogic.noteCatalog(
            registry, roomId: room, generatedAt: now, machineName: "Review Mac"
        )
        model.connectionRegistry = registry
        model.roomRuntime[room] = AppModel.RoomRuntime(socketUp: true, socketUpSince: now)
        assertRendered(List {
            SettingsConnectionSection(onPair: {}, onForgetAll: {})
                .environmentObject(model)
        })

        let session = try XCTUnwrap(model.sessions.first)
        model.sessionSourceRooms[session.sessionId] = [room]
        assertRendered(CapabilityChatDestination(
            target: CapabilityChatTarget(
                kind: "chat", roomId: room, sessionId: session.sessionId
            ), createdAt: now
        ).environmentObject(model))
        assertRendered(CapabilityChatDestination(
            target: CapabilityChatTarget(
                kind: "chat", roomId: "wrong-room", sessionId: session.sessionId
            ), createdAt: now
        ).environmentObject(model))
    }

    func testDeliveryStatesAndMcpDataIconRender() {
        let now = Date().timeIntervalSince1970 * 1_000
        let deliveries = [
            surfaceDelivery(id: "queued", state: .queued, at: now - 3),
            surfaceDelivery(id: "sending", state: .sending, at: now - 2),
            surfaceDelivery(id: "failed", state: .failed, at: now - 1),
            surfaceDelivery(id: "rejected", state: .failed, at: now,
                            admissionRejected: true),
            surfaceDelivery(id: "delivered", state: .delivered, at: now),
        ]
        assertRendered(VStack {
            DeliveryStatusList(deliveries: deliveries).environmentObject(model)
        })

        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let source = "data:image/png;base64,\(image.pngData()!.base64EncodedString())"
        assertRendered(MCPServerIcon(
            icon: McpIconInfo(src: source, mimeType: "image/png", sizes: ["4x4"],
                              theme: "light", sourceOrigin: nil),
            size: 48
        ))
    }

    private func surfacePairing(room: String) -> Pairing {
        Pairing(
            relayUrl: "ws://127.0.0.1:1", room: room, role: "phone",
            deviceName: "Review Mac", senderId: "surface",
            myPublicKey: "public", mySecretKey: "secret", peerPublicKey: "peer"
        )
    }

    private func surfaceDelivery(
        id: String, state: DeliveryState, at: Double, admissionRejected: Bool? = nil
    ) -> OutgoingDelivery {
        OutgoingDelivery(
            id: id, text: "Run release checks", agent: "codex", cwd: "/repo",
            sessionId: AppModelDemoFixtures.codexSessionId, requestId: nil,
            roomId: nil, attachments: [], preferredMcp: nil, skill: nil,
            createdAt: at, updatedAt: at, attempts: 1, state: state,
            error: state == .failed ? "Offline" : nil, nextRetryAt: nil,
            admissionRejected: admissionRejected
        )
    }

    private func assertRendered<V: View>(
        _ view: V,
        minimumBytes: Int = 4_000,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        let image = UIGraphicsImageRenderer(size: frame.size).image { _ in
            controller.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, minimumBytes,
                             file: file, line: line)
        window.isHidden = true
    }
}

private struct SurfaceBindingHost: View {
    @EnvironmentObject private var model: AppModel
    @State private var attachments = [AttachmentDraft(
        name: "notes.txt", mimeType: "text/plain", data: Data("hello".utf8)
    )]
    @State private var mcp: String? = "github"
    @State private var skill: String? = "ios-qa"
    @State private var workspace = "/Users/reviewer/granttap"

    var body: some View {
        VStack {
            AttachmentStrip(attachments: $attachments)
            MessageRoutingStrip(selectedMcp: $mcp, selectedSkill: $skill)
            WorkspaceSelectionMenu(
                agent: "codex", selection: $workspace,
                folders: ["/Users/reviewer/granttap", "/tmp/sample"]
            )
        }
    }
}

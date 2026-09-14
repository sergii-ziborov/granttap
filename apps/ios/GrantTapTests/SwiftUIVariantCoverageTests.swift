import AVFoundation
import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class SwiftUIVariantCoverageTests: XCTestCase {
    private var model: AppModel!

    override func setUp() async throws {
        model = AppModel.shared
        model.startDemo()
    }

    override func tearDown() async throws {
        CapabilityUsageStore.shared.clear()
        model.stopDemo()
        model = nil
    }

    func testConnectionSettingsRenderEmptyAndEveryHealthPhase() {
        model.stopDemo()
        defer { model.startDemo() }
        model.connectionRegistry = .empty
        model.roomRuntime = [:]
        assertRendered(List {
            SettingsConnectionSection(onPair: {}, onForgetAll: {})
                .environmentObject(model)
        })

        let now = Date().timeIntervalSince1970 * 1_000
        renderConnection(room: "phone-offline", runtime: .init(), catalogAt: 0, now: now)
        renderConnection(
            room: "mac-offline",
            runtime: .init(socketUp: true, socketUpSince: now),
            catalogAt: 0, now: now
        )
        renderConnection(
            room: "need-repair",
            runtime: .init(socketUp: true, socketUpSince: now - 200_000),
            catalogAt: 0, now: now
        )
        renderConnection(
            room: "live-computer",
            runtime: .init(socketUp: true, socketUpSince: now - 1_000),
            catalogAt: now, now: now, includeLoad: true
        )
    }

    func testUsageHistoryRendersMetricsOutcomesAndAuthenticatedChatLinks() {
        let store = CapabilityUsageStore.shared
        store.clear()
        let room = "usage-room"
        let sessionId = try! XCTUnwrap(model.sessions.first?.sessionId)
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: pairing(room: room)
        )
        model.sessionSourceRooms[sessionId] = [room]
        let now = Date().timeIntervalSince1970 * 1_000 + 2_000
        for (index, outcome) in CapabilityOutcome.allCases.enumerated() {
            store.record(
                .mcp, name: "github", sessionId: sessionId,
                sourceId: "mcp-\(index)", createdAt: now + Double(index),
                toolName: index == 0 ? "mcp__github__search" : "search",
                estimatedContextTokens: 20 + index,
                estimatedBaselineTokens: 60 + index,
                durationMs: 40 + index, outcome: outcome,
                errorClass: outcome == .error ? "remote" : nil,
                sourceNamespace: room, agent: "codex", model: "gpt-5.6-sol"
            )
        }
        store.record(
            .cli, name: "Bash", sessionId: nil, sourceId: "cli",
            createdAt: now + 10, toolName: "exec_command",
            commandPreview: "npm test", durationMs: 1_250,
            outcome: .success, agent: "codex"
        )
        store.record(
            .skill, name: "documents", sessionId: nil, sourceId: "skill",
            createdAt: now + 11, outcome: .unknown, agent: "claude"
        )

        assertRendered(NavigationView {
            CapabilityUsageHistoryView(
                kind: .mcp, name: "github", agent: "codex", modelName: "gpt-5.6-sol"
            )
        })
        assertRendered(NavigationView {
            CapabilityUsageHistoryView(kind: .cli, name: "Bash", agent: "codex", modelName: nil)
        })
        assertRendered(NavigationView {
            CapabilityUsageHistoryView(
                kind: .skill, name: "documents", agent: "claude", modelName: nil
            )
        })
    }

    func testTaskChatRendersOfflineEmptyKnownEmptyAndCapabilityComputations() throws {
        let session = try XCTUnwrap(model.sessions.first)
        let originalActivities = model.activities
        let originalRegistry = model.connectionRegistry
        let originalRooms = model.sessionSourceRooms
        let originalConnected = model.connected
        defer {
            model.activities = originalActivities
            model.connectionRegistry = originalRegistry
            model.sessionSourceRooms = originalRooms
            model.connected = originalConnected
        }

        let room = "chat-room"
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: pairing(room: room)
        )
        model.sessionSourceRooms[session.sessionId] = [room]
        let store = CapabilityUsageStore.shared
        store.clear()
        let now = Date().timeIntervalSince1970 * 1_000 + 1_000
        store.record(
            .cli, name: "Bash", sessionId: session.sessionId,
            sourceId: "shell-a", createdAt: now, commandPreview: "npm test",
            estimatedContextTokens: 50, sourceNamespace: room
        )
        store.record(
            .cli, name: "Bash", sessionId: session.sessionId,
            sourceId: "shell-b", createdAt: now + 1, commandPreview: "swift test",
            estimatedContextTokens: 70, sourceNamespace: room
        )

        let chat = TaskChatView(session: session)
        XCTAssertEqual(TaskChatView.threadIndent(-1), 0)
        XCTAssertEqual(TaskChatView.threadIndent(9), 64)

        model.activities[session.sessionId] = nil
        model.connected = false
        assertRendered(NavigationView { chat.environmentObject(model) })

        model.connected = true
        model.activities[session.sessionId] = SessionActivity(
            sessionId: session.sessionId, agent: session.agent, state: "idle",
            entries: [], generatedAt: now
        )
        // The timeout must be seeded through the initializer: assigning to a
        // @State property of an unrendered copy never reaches the live view.
        assertRendered(NavigationView {
            TaskChatView(session: session, initialLoadTimedOut: true).environmentObject(model)
        })

        model.activities[session.sessionId] = nil
        assertRendered(NavigationView { chat.environmentObject(model) })
        if let second = model.sessions.dropFirst().first {
            assertRendered(NavigationView {
                TaskChatView(session: second).environmentObject(model)
            })
        }
    }

    func testPairingSheetRendersErrorBusyTokenAndScannerVariants() {
        let key = Data(repeating: 9, count: 32)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "\(String(repeating: "a", count: Pairing.mailboxLength)).\(key)"
        assertRendered(PairingSheet(
            json: "not a pairing", error: "Pairing expired", secureToken: token,
            cameraAuthorization: VariantCameraAuthorization(status: .denied)
        ).environmentObject(model))
        assertRendered(PairingSheet(
            secureToken: token, busy: true,
            cameraAuthorization: VariantCameraAuthorization(status: .restricted)
        ).environmentObject(model))
        assertRendered(PairingSheet(
            scanning: true,
            cameraAuthorization: VariantCameraAuthorization(status: .denied)
        ).environmentObject(model))
    }

    private func renderConnection(
        room: String, runtime: AppModel.RoomRuntime, catalogAt: Double,
        now: Double, includeLoad: Bool = false
    ) {
        var registry = ConnectionRegistryLogic.upsert(
            .empty, pairing: pairing(room: room), now: now - 300_000
        )
        if catalogAt > 0 {
            registry = ConnectionRegistryLogic.noteCatalog(
                registry, roomId: room, generatedAt: catalogAt, machineName: "Review Mac"
            )
        }
        model.connectionRegistry = registry
        model.roomRuntime = [room: runtime]
        model.machineLoadByRoom = [:]
        if includeLoad {
            model.machineLoadByRoom[room] = MachineLoad(
                machine: "Review Mac", monitorCpuPercent: 4.5,
                monitorMemoryBytes: 64 * 1_024 * 1_024,
                agents: [
                    AgentLoadSample(
                        agent: "codex", processes: 2, cpuPercent: 25,
                        memoryBytes: 512 * 1_024 * 1_024, sessions: 3,
                        scanMs: 850, tokensRecent: 1_500
                    ),
                    AgentLoadSample(agent: "claude", processes: 0),
                ], generatedAt: now
            )
        }
        assertRendered(List {
            SettingsConnectionSection(onPair: {}, onForgetAll: {})
                .environmentObject(model)
        })
        assertRendered(ConnectionDetailSheet().environmentObject(model))
    }

    private func pairing(room: String) -> Pairing {
        Pairing(
            relayUrl: "ws://127.0.0.1:1", room: room, role: "phone",
            deviceName: "Review Mac", senderId: "variant",
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
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        let image = UIGraphicsImageRenderer(size: frame.size).image { _ in
            controller.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 4_000, file: file, line: line)
        window.isHidden = true
    }
}

private struct VariantCameraAuthorization: QRScannerCameraAuthorizing {
    let status: AVAuthorizationStatus
    var videoStatus: AVAuthorizationStatus { status }
    func requestVideoAccess(_ completion: @escaping (Bool) -> Void) { completion(false) }
}

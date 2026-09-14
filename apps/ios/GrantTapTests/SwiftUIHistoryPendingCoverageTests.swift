import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class SwiftUIHistoryPendingCoverageTests: XCTestCase {
    private var model: AppModel!

    override func setUp() async throws {
        model = AppModel.shared
        model.startDemo()
    }

    override func tearDown() async throws {
        model.stopDemo()
        model = nil
    }

    func testHistoryRowsAndDetailRenderRichKnownAndUnknownSnapshots() throws {
        var session = try XCTUnwrap(model.sessions.last)
        session.skills = [
            SkillInfo(name: "allowed", allowed: true),
            SkillInfo(name: "blocked", allowed: false),
        ]
        session.mcpServers = [
            McpServerInfo(name: "github", configuredEnabled: true, allowed: true),
            McpServerInfo(name: "figma", configuredEnabled: true, allowed: false),
        ]
        let live = ChatComputerRoute(roomId: "live", computerName: "Review Mac", phase: .live)
        let offline = ChatComputerRoute(
            roomId: "offline", computerName: "Travel Mac", phase: .macOffline
        )
        assertRendered(VStack {
            HistoryRow(session: session, archived: false, route: live)
            HistoryRow(session: session, archived: true, route: offline)
            HistoryRow(session: session, archived: false, route: nil)
        }.padding())

        let now = Date().timeIntervalSince1970 * 1_000
        model.activities[session.sessionId] = SessionActivity(
            sessionId: session.sessionId, agent: session.agent, state: "idle",
            entries: [
                ActivityEntry(id: "message", kind: "message", text: "Finished", createdAt: now),
                ActivityEntry(id: "tool", kind: "tool", text: "npm test", createdAt: now + 1),
            ], generatedAt: now
        )
        model.archivedSessionIds.insert(session.sessionId)
        assertRendered(NavigationView {
            HistoricalChatDetail(session: session).environmentObject(model)
        })

        model.activities[session.sessionId] = SessionActivity(
            sessionId: session.sessionId, agent: session.agent, state: "idle",
            entries: [], generatedAt: now
        )
        assertRendered(NavigationView {
            HistoricalChatDetail(session: session).environmentObject(model)
        })
        model.activities[session.sessionId] = nil
        model.archivedSessionIds.remove(session.sessionId)
        assertRendered(NavigationView {
            HistoricalChatDetail(session: session).environmentObject(model)
        })
    }

    func testNeedsYouRendersPermissionQuestionDeliveryAndRiskVariants() throws {
        let sessionId = try XCTUnwrap(model.sessions.first?.sessionId)
        let now = Date().timeIntervalSince1970 * 1_000
        model.pending = [
            request(id: "safe", agent: "codex", tool: "Bash", danger: .safe, at: now),
            request(id: "caution", agent: "codex", tool: "Bash", danger: .caution, at: now + 1),
            request(id: "danger", agent: "codex", tool: "Bash", danger: .dangerous, at: now + 2),
            request(id: "destroy", agent: "codex", tool: "Bash", danger: .destructive, at: now + 3),
        ]
        model.focusedApprovalId = "destroy"
        model.questions = [AgentEvent(
            type: "agent.event", text: "Which branch?", requestId: "question",
            kind: "question", sessionId: sessionId, createdAt: now + 4
        )]
        model.deliveries = [failedDelivery(id: "failed", sessionId: sessionId, at: now + 5)]
        assertRendered(ContentView().environmentObject(model), minimumBytes: 14_000)
    }

    func testNeedsYouRendersMcpOpenYesNoAndSubmittingVariants() {
        let now = Date().timeIntervalSince1970 * 1_000
        model.pending = [
            request(id: "yes-no", agent: "granttap", tool: "ask_yes_no",
                    danger: nil, at: now),
            request(id: "open", agent: "granttap", tool: "ask", danger: nil, at: now + 1),
        ]
        model.questions = [AgentEvent(
            type: "agent.event", text: "Reply later", requestId: "waiting-question",
            kind: "question", sessionId: nil, createdAt: now + 2
        )]
        model.approvalDecisionsInFlight = [
            "open": "reply", "waiting-question": "reply",
        ]
        assertRendered(ContentView().environmentObject(model), minimumBytes: 12_000)

        model.approvalDecisionsInFlight = ["yes-no": "yes"]
        model.questions = []
        assertRendered(ContentView().environmentObject(model), minimumBytes: 12_000)
    }

    func testInChatNeedsYouRendersScopedFallbackMcpAndInFlightVariants() {
        let now = Date().timeIntervalSince1970 * 1_000
        let sessionId = AppModelDemoFixtures.codexSessionId
        model.pending = [
            request(id: "permission", agent: "codex", tool: "Bash",
                    danger: .dangerous, at: now, sessionId: sessionId),
            request(id: "yes-no", agent: "granttap", tool: "ask_yes_no",
                    danger: nil, at: now + 1, sessionId: sessionId),
        ]
        model.questions = [AgentEvent(
            type: "agent.event", text: "What next?", requestId: "question",
            kind: "question", sessionId: sessionId, createdAt: now + 2
        )]
        assertRendered(InChatApprovalsBar(sessionId: sessionId, onReply: { _ in })
            .environmentObject(model))

        model.pending = [
            request(id: "open", agent: "granttap", tool: "ask",
                    danger: nil, at: now, sessionId: nil),
        ]
        model.questions = [AgentEvent(
            type: "agent.event", text: "Legacy question", requestId: "legacy",
            kind: "question", sessionId: nil, createdAt: now + 1
        )]
        assertRendered(InChatApprovalsBar(sessionId: "different", onReply: { _ in })
            .environmentObject(model))

        model.approvalDecisionsInFlight = ["open": "reply", "legacy": "reply"]
        assertRendered(InChatApprovalsBar(sessionId: nil, onReply: { _ in })
            .environmentObject(model))
        model.pending = []
        model.questions = []
        assertRendered(InChatApprovalsBar(sessionId: sessionId, onReply: { _ in })
            .environmentObject(model), minimumBytes: 100)
    }

    func testCapabilityChatDestinationCoversUnknownExactAndRejectedOwnership() {
        let roomA = "capability-a"
        let roomB = "capability-b"
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            ConnectionRegistryLogic.upsert(.empty, pairing: pairing(room: roomA)),
            pairing: pairing(room: roomB), prefer: false
        )
        assertRendered(CapabilityChatDestination(
            target: CapabilityChatTarget(kind: "chat", roomId: roomA, sessionId: "unknown"),
            createdAt: 1
        ).environmentObject(model))

        model.rememberSessionSourceRoom(roomA, sessionId: "exact")
        assertRendered(CapabilityChatDestination(
            target: CapabilityChatTarget(kind: "chat", roomId: roomA, sessionId: "exact"),
            createdAt: 1
        ).environmentObject(model))

        model.rememberSessionSourceRoom(roomA, sessionId: "rejected")
        assertRendered(CapabilityChatDestination(
            target: CapabilityChatTarget(kind: "chat", roomId: roomB, sessionId: "rejected"),
            createdAt: 1
        ).environmentObject(model))
    }

    private func request(
        id: String, agent: String, tool: String, danger: DangerLevel?, at: Double,
        sessionId: String? = AppModelDemoFixtures.codexSessionId
    ) -> ApprovalRequest {
        ApprovalRequest(
            type: "approval.request", requestId: id, agent: agent,
            kind: "permission", tool: tool, title: "Approve \(id)?",
            command: "npm test", cwd: "/repo",
            sessionId: sessionId,
            risk: danger == nil ? .high : .medium, danger: danger, createdAt: at
        )
    }

    private func pairing(room: String) -> Pairing {
        Pairing(
            relayUrl: "ws://127.0.0.1:1", room: room, role: "phone",
            deviceName: room, senderId: "coverage", myPublicKey: "public",
            mySecretKey: "secret", peerPublicKey: "peer"
        )
    }

    private func failedDelivery(id: String, sessionId: String, at: Double) -> OutgoingDelivery {
        OutgoingDelivery(
            id: id, text: "Continue", agent: "codex", cwd: "/repo",
            sessionId: sessionId, requestId: nil, roomId: nil, attachments: [],
            preferredMcp: nil, skill: nil, createdAt: at, updatedAt: at,
            attempts: 2, state: .failed, error: "Computer offline", nextRetryAt: nil
        )
    }

    private func assertRendered<V: View>(
        _ view: V, minimumBytes: Int = 4_000,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let image = UIGraphicsImageRenderer(size: frame.size).image { _ in
            controller.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, minimumBytes, file: file, line: line)
        window.isHidden = true
    }
}

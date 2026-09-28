import SwiftUI
import XCTest
@testable import GrantTap

/// Every figure on the Usage screen opens what it counted, and each of those
/// screens says something even when there is nothing to say.
@MainActor
final class UsageDrillDownTests: XCTestCase {
    private let now = Date().timeIntervalSince1970 * 1_000

    private func session(_ id: String, tokens: Int, used: Int? = nil, window: Int? = nil) -> SessionInfo {
        var session = SessionInfo(
            sessionId: id, agent: "claude", projectId: "p", taskId: "t", computerId: "MacBook",
            title: "Chat \(id)", state: "working", startedAt: now - 5_000, lastActivityAt: now,
            tokensSession: tokens, tokensLastTurn: 1
        )
        session.contextTokensUsed = used
        session.contextWindow = window
        return session
    }

    private func summary(_ name: String, kind: CapabilityUsageKind, count: Int, failures: Int) -> OperationalToolSummary {
        let events = (0..<count).map { index -> CapabilityUsageEvent in
            var event = CapabilityUsageEvent(
                id: "\(name)-\(index)", sourceId: "\(name)-\(index)", kind: kind, name: name, createdAt: now
            )
            event.outcome = index < failures ? .error : .success
            return event
        }
        return UsageSummaries(events: events, totals: []).rows[0]
    }

    func testEachFigureOpensTheChatsAndCallsItCounted() {
        let sessions = [
            session("busy", tokens: 90_000, used: 180_000, window: 200_000),
            session("quiet", tokens: 1_000),
        ]
        let byTokens = UsageChatsView(title: "Tokens", sessions: sessions, order: .tokens)
        let byActivity = UsageChatsView(title: "Sessions", sessions: sessions)
        RenderProbe.render(NavigationView { byTokens })
        RenderProbe.render(NavigationView { byActivity })
        // A period with nothing in it says so rather than showing an empty list.
        RenderProbe.render(NavigationView { UsageChatsView(title: "Sessions", sessions: []) })

        let tools = [
            summary("rg", kind: .cli, count: 6, failures: 0),
            summary("github", kind: .mcp, count: 3, failures: 2),
        ]
        RenderProbe.render(NavigationView { UsageToolListView(title: "Tool calls", summaries: tools) })
        RenderProbe.render(NavigationView {
            UsageToolListView(title: "Skills used", summaries: [], agent: "claude")
        })
    }

    /// These two screens read the model the whole app shares, so the test
    /// fills it, renders, and puts back exactly what it found.
    func testWhatWaitsAndWhichComputersAreAwakeEachOpenTheirOwnScreen() {
        let model = AppModel.shared
        let previous = (model.pending, model.questions, model.sessions,
                        model.connectionRegistry, model.machineLoadByRoom)
        defer {
            (model.pending, model.questions, model.sessions,
             model.connectionRegistry, model.machineLoadByRoom) = previous
        }
        model.pending = []
        model.questions = []
        model.sessions = []
        model.connectionRegistry = .empty
        model.machineLoadByRoom = [:]
        // Nothing waiting and nothing linked: both screens say so.
        RenderProbe.render(NavigationView { UsageWaitingView() })
        RenderProbe.render(NavigationView { UsageComputersView() })

        let chat = session("busy", tokens: 90_000)
        model.sessions = [chat]
        model.pending = [ApprovalRequest(
            type: "approval.request", requestId: "r-1", agent: "claude", kind: "tool",
            tool: "Bash", title: "Publish the release build?", command: "npm run deploy",
            cwd: nil, sessionId: "busy", risk: .medium, danger: nil, createdAt: now
        )]
        model.questions = [
            AgentEvent(type: "agent.event", text: "Should I run the regression suite?",
                       requestId: "q-1", kind: "question", sessionId: "busy", createdAt: now),
            // No chat to land in: the row is a row and not a link.
            AgentEvent(type: "agent.event", text: "Which branch?", requestId: nil,
                       kind: "question", sessionId: nil, createdAt: now),
        ]
        RenderProbe.render(NavigationView { UsageWaitingView() }, height: 1_200)

        // A linked computer, one agent running on it and one that is not.
        let room = "usage-computers-room"
        let pairing = PairingFixture.pairing(room: room, deviceName: "Review Mac")
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing, mode: .add, prefer: true)
        model.machineLoadByRoom[room] = MachineLoad(
            machine: "Review Mac", monitorCpuPercent: 4.5, monitorMemoryBytes: 64 * 1_024 * 1_024,
            agents: [
                AgentLoadSample(agent: "claude", processes: 3, cpuPercent: 18,
                                memoryBytes: 512 * 1_024 * 1_024, sessions: 2,
                                scanMs: 640, tokensRecent: 2_400),
            ], generatedAt: now
        )
        RenderProbe.render(NavigationView { UsageComputersView() }, height: 1_200)
        // A computer that has reported nothing says that, rather than nothing.
        model.machineLoadByRoom = [:]
        RenderProbe.render(NavigationView { UsageComputersView() }, height: 1_200)
    }
}

import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class AgentLoadDrillDownTests: XCTestCase {
    private func session(_ id: String, agent: String = "claude", title: String? = nil, tokens: Int = 0) -> SessionInfo {
        var info = SessionInfo(sessionId: id, agent: agent, cwd: "/repo", state: "working", startedAt: 1,
                               lastActivityAt: 2, tokensSession: tokens, tokensLastTurn: 0)
        info.title = title
        return info
    }

    func testTheWireCarriesEachProcessEachChatAndTheDiskAndAnOlderComputerSendsNone() throws {
        let json = """
        {"type":"machine.load","machine":"Mac","monitorCpuPercent":1,"monitorMemoryBytes":2,"generatedAt":3,
         "agents":[{"agent":"claude","processes":3,"cpuPercent":40,"memoryBytes":3e9,"sessions":2,"scanMs":10,"tokensRecent":0,
                    "processList":[{"pid":12,"name":"node","cpuPercent":30,"memoryBytes":1e9,"detail":"vitest --run","sessionId":"a"},
                                   {"pid":10,"name":"claude","cpuPercent":10,"memoryBytes":2e9}],
                    "chats":[{"sessionId":"a","processes":2,"cpuPercent":40,"memoryBytes":3e9}],
                    "disk":{"measuredAt":1,"totalBytes":5e8,"entries":[{"path":"~/.claude/projects","bytes":4e8},{"path":"…","bytes":1e8}]}},
                   {"agent":"codex","processes":1,"cpuPercent":0,"memoryBytes":0,"sessions":0,"scanMs":0,"tokensRecent":0}]}
        """
        let decoded = try JSONDecoder().decode(MachineLoad.self, from: Data(json.utf8))
        let claude = decoded.agents[0]
        XCTAssertEqual(claude.processList.map(\.pid), [12, 10])
        XCTAssertEqual(claude.processList[0].sessionId, "a")
        XCTAssertNil(claude.processList[1].detail)
        XCTAssertEqual(claude.chats.first?.processes, 2)
        XCTAssertEqual(claude.disk?.entries.count, 2)
        XCTAssertEqual(decoded.agents[1].processList, [])
        XCTAssertEqual(decoded.agents[1].chats, [])
        XCTAssertNil(decoded.agents[1].disk)
        XCTAssertEqual(AgentProcessListView.share(of: claude.processList[0], in: claude), 0.75, accuracy: 0.001)
        let idle = AgentLoadSample(agent: "codex", cpuPercent: 0, memoryBytes: 100,
                                   processList: [ProcessLoadRow(pid: 1, name: "codex", cpuPercent: 0, memoryBytes: 25)])
        XCTAssertEqual(AgentProcessListView.share(of: idle.processList[0], in: idle), 0.25, accuracy: 0.001)
        XCTAssertEqual(AgentProcessListView.share(of: idle.processList[0], in: AgentLoadSample(agent: "codex")), 0)
    }

    func testChatsAreJoinedWithWhatThePhoneKnowsHeaviestFirst() {
        let sample = AgentLoadSample(
            agent: "claude", processes: 5, cpuPercent: 50, memoryBytes: 4e9, sessions: 3,
            chats: [
                ChatProcessLoad(sessionId: "quiet", processes: 1, cpuPercent: 0, memoryBytes: 1e8),
                ChatProcessLoad(sessionId: "busy", processes: 3, cpuPercent: 45, memoryBytes: 3e9),
                ChatProcessLoad(sessionId: "gone", processes: 1, cpuPercent: 5, memoryBytes: 9e8),
            ]
        )
        let sessions = [
            session("busy", title: "Build 77", tokens: 5_000),
            session("quiet", title: "Idle chat", tokens: 100),
            session("unmeasured", title: "Open, ran nothing", tokens: 9_000),
            session("other", agent: "codex", title: "Not this agent"),
            session("busy", title: "duplicate row from history"),
        ]
        let rows = AgentChatLoadRows.rows(sample: sample, sessions: sessions)
        XCTAssertEqual(rows.map(\.sessionId), ["busy", "gone", "quiet", "unmeasured"])
        XCTAssertEqual(rows[0].title, "Build 77")
        XCTAssertEqual(rows[1].title, "gone", "a chat the phone never saw is named by its id")
        XCTAssertNil(rows[3].load)
        XCTAssertEqual(AgentChatLoadRows.share(of: rows[0], in: rows), 0.9, accuracy: 0.001)
        XCTAssertEqual(AgentChatLoadRows.share(of: rows[3], in: rows), 0)
        XCTAssertEqual(AgentChatLoadView.detailParts(rows[0]).first, "3 processes")
        XCTAssertTrue(AgentChatLoadView.detailParts(rows[0]).contains("5.0k tok") || AgentChatLoadView.detailParts(rows[0]).contains { $0.hasSuffix("tok") })
        XCTAssertEqual(AgentChatLoadView.detailParts(rows[3]).first, L("no measured process"))
        // With no CPU anywhere, memory decides the share.
        let cold = AgentLoadSample(agent: "claude", chats: [ChatProcessLoad(sessionId: "a", processes: 1, cpuPercent: 0, memoryBytes: 3e8),
                                                            ChatProcessLoad(sessionId: "b", processes: 1, cpuPercent: 0, memoryBytes: 1e8)])
        let coldRows = AgentChatLoadRows.rows(sample: cold, sessions: [])
        XCTAssertEqual(AgentChatLoadRows.share(of: coldRows[0], in: coldRows), 0.75, accuracy: 0.001)
    }

    func testTheThreeScreensRenderWithDataAndWithout() {
        let room = "drill-\(UUID().uuidString)"
        let model = AppModel()
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: Pairing(relayUrl: "ws://127.0.0.1:1", room: room, role: "phone", deviceName: "Mac",
                                     senderId: "s", myPublicKey: "p", mySecretKey: "k", peerPublicKey: "q"),
            prefer: true, now: 1
        )
        let empty = AgentLoadSample(agent: "claude", processes: 2, sessions: 1)
        model.recordMachineLoad(MachineLoad(machine: "Mac", monitorCpuPercent: 0, monitorMemoryBytes: 0, agents: [empty], generatedAt: 1), fromRoom: room)
        RenderProbe.render(NavigationView { AgentProcessListView(room: room, agent: "claude").environmentObject(model) })
        RenderProbe.render(NavigationView { AgentChatLoadView(room: room, agent: "claude").environmentObject(model) })
        RenderProbe.render(NavigationView { AgentDiskView(room: room, agent: "claude").environmentObject(model) })

        let full = AgentLoadSample(
            agent: "claude", processes: 2, cpuPercent: 40, memoryBytes: 3e9, sessions: 1,
            processList: [ProcessLoadRow(pid: 12, name: "node", cpuPercent: 30, memoryBytes: 1e9, detail: "vitest --run", sessionId: "a"),
                          ProcessLoadRow(pid: 10, name: "claude", cpuPercent: 10, memoryBytes: 2e9)],
            chats: [ChatProcessLoad(sessionId: "a", processes: 2, cpuPercent: 40, memoryBytes: 3e9)],
            disk: AgentDiskUsage(measuredAt: 1, totalBytes: 5e8, entries: [DiskUsageEntry(path: "~/.claude/projects", bytes: 4e8), DiskUsageEntry(path: "…", bytes: 1e8)])
        )
        model.sessions = [session("a", title: "Build 77", tokens: 500)]
        model.recordMachineLoad(MachineLoad(machine: "Mac", monitorCpuPercent: 0, monitorMemoryBytes: 0, agents: [full], generatedAt: 2), fromRoom: room)
        RenderProbe.render(NavigationView { AgentProcessListView(room: room, agent: "claude").environmentObject(model) })
        RenderProbe.render(NavigationView { AgentChatLoadView(room: room, agent: "claude").environmentObject(model) })
        RenderProbe.render(NavigationView { AgentDiskView(room: room, agent: "claude").environmentObject(model) })
        RenderProbe.render(NavigationView { AgentLoadDetailView(room: room, agent: "claude").environmentObject(model) })
        // An agent the computer never reported.
        RenderProbe.render(NavigationView { AgentChatLoadView(room: room, agent: "grok").environmentObject(model) })
        LoadHistoryPersistence.remove(room: room)
    }
}

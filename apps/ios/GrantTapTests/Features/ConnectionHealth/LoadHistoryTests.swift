import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class LoadHistoryTests: XCTestCase {
    private func load(at: Double, cpu: Double, processes: Int = 3, groups: [ProcessGroupLoad] = []) -> MachineLoad {
        MachineLoad(
            machine: "Mac", monitorCpuPercent: 1, monitorMemoryBytes: 2,
            agents: [AgentLoadSample(agent: "claude", processes: processes, cpuPercent: cpu, memoryBytes: 1_000 * cpu,
                                     sessions: 1, topProcesses: groups)],
            generatedAt: at
        )
    }

    func testAnHourOfReadingsIsKeptBoundedAndSampledByPeak() {
        let hour = LoadHistory.windowMs
        var points: [LoadHistoryPoint] = []
        points = LoadHistory.appending(load(at: 0, cpu: 5), to: points, now: 0)
        points = LoadHistory.appending(load(at: 10_000, cpu: 40), to: points, now: 10_000)
        points = LoadHistory.appending(load(at: hour + 5_000, cpu: 8), to: points, now: hour + 5_000)
        XCTAssertEqual(points.map(\.at), [10_000, hour + 5_000], "the reading from over an hour ago is gone")
        XCTAssertEqual(points.last?.cpu(of: "claude"), 8)
        XCTAssertEqual(points.last?.agentCpuTotal, 8)
        XCTAssertEqual(points.last?.processes(of: "claude"), 3)
        XCTAssertNil(points.last?.memory(of: "codex"))

        // A reading older than the newest is not replayed in front of it.
        points = LoadHistory.appending(load(at: hour + 4_000, cpu: 99), to: points, now: hour + 5_000)
        XCTAssertEqual(points.map(\.at), [10_000, hour + 5_000, hour + 4_000].sorted(), "readings stay ordered by time")

        var many: [LoadHistoryPoint] = []
        for index in 0..<(LoadHistory.maxPoints + 20) {
            many = LoadHistory.appending(load(at: Double(index) * 1_000, cpu: 1), to: many, now: Double(index) * 1_000)
        }
        XCTAssertEqual(many.count, LoadHistory.maxPoints)

        // Slots hold the peak that fell in them; empty slots stay empty.
        let series = LoadHistory.series([
            LoadHistoryPoint(at: 1_000, agents: [.init(agent: "claude", cpuPercent: 10, memoryBytes: 1, processes: 1)]),
            LoadHistoryPoint(at: 1_500, agents: [.init(agent: "claude", cpuPercent: 30, memoryBytes: 1, processes: 1)]),
            LoadHistoryPoint(at: 9_000, agents: [.init(agent: "claude", cpuPercent: 5, memoryBytes: 1, processes: 1)]),
        ], slots: 4, since: 0, until: 10_000) { $0.cpu(of: "claude") }
        XCTAssertEqual(series, [30, nil, nil, 5])
        XCTAssertEqual(LoadHistory.series([], slots: 0, since: 0, until: 1) { _ in 1 }, [])
    }

    func testReadingsSurviveALaunchAndAreRecordedPerComputer() {
        let room = "load-room-\(UUID().uuidString)"
        LoadHistoryPersistence.remove(room: room)
        XCTAssertEqual(LoadHistoryPersistence.load(room: room), [])
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        model.recordMachineLoad(load(at: now - 60_000, cpu: 12), fromRoom: room)
        model.recordMachineLoad(load(at: now, cpu: 20, groups: [.init(name: "node", count: 19, cpuPercent: 18, memoryBytes: 5e8)]), fromRoom: room)
        XCTAssertEqual(model.machineLoadHistoryByRoom[room]?.count, 2)
        XCTAssertEqual(model.machineLoadByRoom[room]?.agents.first?.topProcesses.first?.name, "node")
        // Writes are spaced out; going to the background writes what is left.
        LoadHistoryPersistence.flush()
        XCTAssertEqual(LoadHistoryPersistence.load(room: room).count, 2, "written for the next launch")
        let fresh = AppModel()
        XCTAssertEqual(fresh.loadHistory(room: room).count, 2, "read back on first use")
        LoadHistoryPersistence.remove(room: room)
        XCTAssertEqual(LoadHistoryPersistence.load(room: room), [])
    }

    func testTheAgentDetailAndChartsRender() throws {
        let room = "detail-room-\(UUID().uuidString)"
        let now = Date().timeIntervalSince1970 * 1_000
        let model = AppModel()
        for step in 0..<12 {
            model.recordMachineLoad(
                load(at: now - Double(11 - step) * 300_000, cpu: Double(step * 7), processes: 10 + step,
                     groups: [.init(name: "node", count: 19, cpuPercent: 18, memoryBytes: 5e8),
                              .init(name: "zsh", count: 10, cpuPercent: 0.3, memoryBytes: 4e6)]),
                fromRoom: room
            )
        }
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            .empty, pairing: Pairing(relayUrl: "ws://127.0.0.1:1", room: room, role: "phone", deviceName: "Mac",
                                     senderId: "s", myPublicKey: "p", mySecretKey: "k", peerPublicKey: "q"),
            prefer: true, now: now
        )
        let detail = AgentLoadDetailView(room: room, agent: "claude").environmentObject(model)
        RenderProbe.render(NavigationView { detail })
        RenderProbe.render(NavigationView { AgentLoadDetailView(room: room, agent: "codex").environmentObject(model) })
        RenderProbe.render(ConnectionDetailSheet().environmentObject(model))
        RenderProbe.render(LoadHistoryChart(values: [nil, 1, 2, nil, 4], accent: .blue, startLabel: "a", endLabel: "b"))
        RenderProbe.render(LoadHistoryChart(values: [nil, nil], accent: .blue, startLabel: "a", endLabel: "b"))
        RenderProbe.render(LoadHistoryChart(values: [3], accent: .blue, startLabel: "a", endLabel: "b"))
        LoadHistoryPersistence.remove(room: room)

        // The wire form carries what the agent runs; an older computer sends nothing and decodes fine.
        let json = """
        {"type":"machine.load","machine":"Mac","monitorCpuPercent":1,"monitorMemoryBytes":2,"generatedAt":3,
         "agents":[{"agent":"claude","processes":38,"cpuPercent":24.4,"memoryBytes":2e9,"sessions":2,"scanMs":10,"tokensRecent":0,
                    "topProcesses":[{"name":"node","count":19,"cpuPercent":22.9,"memoryBytes":5.7e8}]},
                   {"agent":"codex","processes":1,"cpuPercent":0,"memoryBytes":0,"sessions":0,"scanMs":0,"tokensRecent":0}]}
        """
        let decoded = try JSONDecoder().decode(MachineLoad.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.agents[0].topProcesses.map(\.name), ["node"])
        XCTAssertEqual(decoded.agents[1].topProcesses, [])
    }
}

@MainActor
final class LoadReportPolicyTests: XCTestCase {
    private func load(at: Double, rich: Bool) -> MachineLoad {
        MachineLoad(
            machine: "Mac", monitorCpuPercent: 0, monitorMemoryBytes: 0,
            agents: [AgentLoadSample(
                agent: "claude", processes: rich ? 40 : 2, cpuPercent: rich ? 30 : 0, memoryBytes: 1,
                processList: rich ? [ProcessLoadRow(pid: 1, name: "node", cpuPercent: 30, memoryBytes: 1)] : []
            )],
            generatedAt: at
        )
    }

    func testAReportThatKnowsLessThanTheOneAMinuteAgoIsTheOlderReporter() {
        let rich = load(at: 1_000, rich: true)
        XCTAssertTrue(LoadReportPolicy.supersedes(rich, over: load(at: 6_000, rich: false)))
        XCTAssertFalse(LoadReportPolicy.supersedes(rich, over: load(at: 70_000, rich: false)), "a minute without a richer report, and the poorer one counts")
        XCTAssertFalse(LoadReportPolicy.supersedes(rich, over: load(at: 6_000, rich: true)))
        XCTAssertFalse(LoadReportPolicy.supersedes(load(at: 1_000, rich: false), over: load(at: 6_000, rich: false)))

        let room = "policy-\(UUID().uuidString)"
        let model = AppModel()
        model.recordMachineLoad(rich, fromRoom: room)
        model.recordMachineLoad(load(at: 6_000, rich: false), fromRoom: room)
        XCTAssertEqual(model.machineLoadByRoom[room]?.agents.first?.processes, 40, "the flicker is not recorded")
        XCTAssertEqual(model.machineLoadHistoryByRoom[room]?.count, 1)
        model.recordMachineLoad(load(at: 70_000, rich: false), fromRoom: room)
        XCTAssertEqual(model.machineLoadByRoom[room]?.agents.first?.processes, 2)
        LoadHistoryPersistence.remove(room: room)
    }

    func testHistoryIsWrittenTwiceAMinuteNotOnEverySample() {
        let room = "throttle-\(UUID().uuidString)"
        let point = LoadHistoryPoint(at: 1)
        LoadHistoryPersistence.scheduleSave([point], room: room, now: 100_000)
        LoadHistoryPersistence.scheduleSave([point, LoadHistoryPoint(at: 2)], room: room, now: 105_000)
        LoadHistoryPersistence.flush()
        XCTAssertEqual(LoadHistoryPersistence.load(room: room).count, 0, "points from the past hour only; these are from 1970")
        LoadHistoryPersistence.remove(room: room)
    }

    func testTheLiveLineFollowsReadingsByTime() {
        let now: Double = 1_000_000
        let points = [
            LoadHistoryPoint(at: now - 200_000, agents: [.init(agent: "claude", cpuPercent: 99, memoryBytes: 1, processes: 1)]),
            LoadHistoryPoint(at: now - 60_000, agents: [.init(agent: "claude", cpuPercent: 10, memoryBytes: 1, processes: 1)]),
            LoadHistoryPoint(at: now - 30_000, agents: [.init(agent: "claude", cpuPercent: 40, memoryBytes: 1, processes: 1)]),
            LoadHistoryPoint(at: now, agents: [.init(agent: "codex", cpuPercent: 5, memoryBytes: 1, processes: 1)]),
        ]
        let readings = LoadHistory.window(points, since: now - LoadLiveChart.windowMs, until: now) { $0.cpu(of: "claude") }
        XCTAssertEqual(readings.map(\.value), [10, 40], "outside the window and other agents are left out")
        let size = CGSize(width: 100, height: 50)
        let first = LoadLiveChart.point(readings[0], in: size, since: now - LoadLiveChart.windowMs, until: now, ceiling: 40)
        XCTAssertEqual(first.x, 50, accuracy: 0.01)
        XCTAssertEqual(first.y, 37.5, accuracy: 0.01)
        XCTAssertFalse(LoadLiveChart.area(readings, in: size, since: now - LoadLiveChart.windowMs, until: now, ceiling: 40).isEmpty)
        XCTAssertTrue(LoadLiveChart.area([readings[0]], in: size, since: 0, until: now, ceiling: 40).isEmpty, "one reading is a dot, not an area")
        RenderProbe.render(LoadLiveChart(points: points, accent: .blue, now: now, format: { "\($0)" }) { $0.cpu(of: "claude") })
        RenderProbe.render(LoadLiveChart(points: [], accent: .blue, now: now) { $0.cpu(of: "claude") })
    }
}

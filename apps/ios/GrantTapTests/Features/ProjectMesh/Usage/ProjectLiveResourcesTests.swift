import XCTest
@testable import GrantTap

final class ProjectLiveResourcesTests: XCTestCase {
    private func snapshot() -> ProjectMeshSnapshot {
        .init(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "repo", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: [
                .init(taskId: "one", sessionId: "same", provider: "claude",
                      computerId: "studio", workspace: "/repo", startedAt: 1),
                .init(taskId: "two", sessionId: "same", provider: "codex",
                      computerId: "air", workspace: "/repo", startedAt: 1),
            ], claims: [], dependencies: [], events: [], generatedAt: 1
        )
    }

    private func load(agent: String, session: String, at: Double) -> MachineLoad {
        MachineLoad(
            machine: "same-hostname", monitorCpuPercent: 3, monitorMemoryBytes: 100,
            agents: [AgentLoadSample(
                agent: agent, processes: 4, cpuPercent: 70, memoryBytes: 8_000,
                chats: [ChatProcessLoad(sessionId: session, processes: 2,
                                        cpuPercent: 35, memoryBytes: 4_000)]
            )], generatedAt: at
        )
    }

    func testLiveSamplesUseRoomProviderAndSessionEvenWithCollidingNativeIds() {
        let now = 1_000_000.0
        let samples = ProjectLiveResources.samples(
            snapshot: snapshot(),
            roomByEndpointId: ["studio": "room-studio", "air": "room-air"],
            loadsByRoom: [
                "room-studio": load(agent: "claude", session: "same", at: now),
                "room-air": load(agent: "codex", session: "same", at: now),
            ], nowMs: now
        )
        XCTAssertEqual(samples.map(\.endpointId), ["air", "studio"])
        XCTAssertEqual(samples.map(\.cpuPercent), [35, 35])
        XCTAssertEqual(samples.map(\.memoryBytes), [4_000, 4_000])
    }

    func testMachineTotalOrStaleSampleDoesNotPretendToBeProjectUsage() {
        let now = 1_000_000.0
        let stale = load(agent: "claude", session: "same", at: now - 130_000)
        let unrelated = load(agent: "codex", session: "foreign", at: now)
        XCTAssertTrue(ProjectLiveResources.samples(
            snapshot: snapshot(),
            roomByEndpointId: ["studio": "room-studio", "air": "room-air"],
            loadsByRoom: ["room-studio": stale, "room-air": unrelated], nowMs: now
        ).isEmpty)
    }

    func testHostAgentLoadIsReportedSeparatelyWhenNoChatCanBeMatched() {
        let now = 1_000_000.0
        let host = load(agent: "codex", session: "foreign", at: now)
        let rooms = ["studio": "room-studio", "air": "room-air"]
        let loads = ["room-air": host]
        XCTAssertTrue(ProjectLiveResources.samples(
            snapshot: snapshot(), roomByEndpointId: rooms,
            loadsByRoom: loads, nowMs: now
        ).isEmpty)
        let shared = ProjectLiveResources.hostSamples(
            snapshot: snapshot(), roomByEndpointId: rooms,
            loadsByRoom: loads, nowMs: now
        )
        XCTAssertEqual(shared.map(\.id), ["air\u{1f}codex"])
        XCTAssertEqual(shared.first?.cpuPercent, 70)
        XCTAssertEqual(shared.first?.memoryBytes, 8_000)
        XCTAssertTrue(ProjectLiveResources.hostSamples(
            snapshot: snapshot(), roomByEndpointId: rooms,
            loadsByRoom: ["room-air": load(agent: "codex", session: "foreign",
                                              at: now - 130_000)], nowMs: now
        ).isEmpty)
    }
}

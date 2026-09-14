import SwiftUI
import XCTest
@testable import GrantTap

/// A Project spans machines, so the question it answers is which machine is
/// carrying it — one neither a task nor global Usage can answer.
final class ProjectUsageStatsTests: XCTestCase {
    private func execution(_ sessionId: String, computer: String) -> ExecutionSessionLink {
        ExecutionSessionLink(
            taskId: "task", sessionId: sessionId, provider: "claude",
            computerId: computer, workspace: "/repo", startedAt: 1
        )
    }

    private func snapshot(_ executions: [ExecutionSessionLink]) -> ProjectMeshSnapshot {
        .init(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: executions, claims: [], dependencies: [], events: [],
            generatedAt: 1
        )
    }

    private func event(
        _ name: String, session: String, cpuMs: Int? = nil, peak: Int? = nil,
        failed: Bool = false
    ) -> CapabilityUsageEvent {
        CapabilityUsageEvent(
            id: "\(name)-\(session)", sourceId: "room:\(name)-\(session)", kind: .cli,
            name: name, sessionId: session, createdAt: 1, toolName: name,
            outcome: failed ? .error : .success,
            resource: cpuMs == nil && peak == nil ? nil : CapabilityResourceUsage(
                attribution: .attributed, cpuTimeMs: cpuMs, peakRssBytes: peak
            )
        )
    }

    func testCallsAreCreditedToTheComputerThatRanThem() {
        let mesh = snapshot([
            execution("s1", computer: "studio"),
            execution("s2", computer: "air"),
        ])
        let rows = ProjectUsageStats.perComputer([
            event("bash", session: "s1", cpuMs: 400, peak: 100),
            event("bash", session: "s1", cpuMs: 600, peak: 900),
            event("bash", session: "s2", cpuMs: 50, peak: 50),
        ], snapshot: mesh)

        // The machine carrying the Project reads first.
        XCTAssertEqual(rows.map(\.endpointId), ["studio", "air"])
        XCTAssertEqual(rows.first?.calls, 2)
        // CPU adds up across calls; memory is a level, so the peak wins.
        XCTAssertEqual(rows.first?.cpuTimeMs, 1_000)
        XCTAssertEqual(rows.first?.peakMemoryBytes, 900)
    }

    func testACallFromAnotherProjectIsNotCounted() {
        let mesh = snapshot([execution("mine", computer: "studio")])
        let events = ProjectUsageStats.events([
            event("bash", session: "mine"),
            event("bash", session: "someone-elses"),
        ], snapshot: mesh)
        XCTAssertEqual(events.count, 1)
        // And an unattributable session credits no machine at all.
        XCTAssertTrue(ProjectUsageStats.perComputer([
            event("bash", session: "someone-elses"),
        ], snapshot: mesh).isEmpty)
    }

    func testFailuresAreReportedPerMachine() {
        let mesh = snapshot([execution("s1", computer: "studio")])
        let rows = ProjectUsageStats.perComputer([
            event("bash", session: "s1"),
            event("bash", session: "s1", failed: true),
        ], snapshot: mesh)
        XCTAssertEqual(rows.first?.failures, 1)
        XCTAssertNil(rows.first?.cpuTimeMs, "no resource was observed, so none is claimed")
    }

    func testAProjectWithNoExecutionsHasNoMachines() {
        let mesh = snapshot([])
        XCTAssertTrue(ProjectUsageStats.sessionIds(mesh).isEmpty)
        XCTAssertTrue(ProjectUsageStats.perComputer(
            [event("bash", session: "s1")], snapshot: mesh
        ).isEmpty)
    }

    /// Mesh status is where a Project's load is read, so it is laid out with a
    /// Project that has some.
    @MainActor
    func testMeshStatusRendersLoadPerComputer() {
        let model = AppModel()
        let run = UUID().uuidString
        let session = "mesh-status-\(run)"
        let mesh = snapshot([execution(session, computer: "studio")])
        model.meshSnapshots[mesh.projectId] = mesh

        // Empty first: a Project with no observed calls draws no load at all.
        RenderProbe.render(ProjectMeshStatusView(snapshot: mesh, model: model))

        CapabilityUsageStore.shared.record(
            .cli, name: "bash", sessionId: session, sourceId: "src-\(run)",
            createdAt: Date().timeIntervalSince1970 * 1_000, toolName: "bash"
        )
        RenderProbe.render(ProjectMeshStatusView(snapshot: mesh, model: model))

        let rows = ProjectUsageStats.perComputer(
            ProjectUsageStats.events(CapabilityUsageStore.shared.events, snapshot: mesh),
            snapshot: mesh
        )
        XCTAssertEqual(rows.first?.endpointId, "studio")
        // The row falls back to the raw endpoint when no computer is paired.
        RenderProbe.render(
            List { ProjectComputerUsageRow(usage: rows[0], model: model) }, height: 200
        )
    }
}

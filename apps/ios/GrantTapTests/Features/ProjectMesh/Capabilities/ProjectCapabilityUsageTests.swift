import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ProjectCapabilityUsageTests: XCTestCase {
    private func snapshot() -> ProjectMeshSnapshot {
        var value = ProjectGovernanceViewFixtures.projectSnapshot()
        value.executions = [
            .init(taskId: "task", sessionId: "same", provider: "claude", computerId: "mac",
                  workspace: "/repo", startedAt: 1),
            .init(taskId: "other", sessionId: "same", provider: "codex", computerId: "workstation",
                  workspace: "/repo", startedAt: 1),
        ]
        return value
    }

    private func event(_ id: String, room: String = "local-mac", provider: String = "claude",
                       kind: CapabilityUsageKind = .mcp, name: String = "github") -> CapabilityUsageEvent {
        .init(id: id, sourceId: id, sourceRoom: room, agent: provider, kind: kind,
              name: name, sessionId: "same", createdAt: 1)
    }

    func testCapabilityHistoryRequiresExactMeshComputerProviderAndName() {
        let rows = ProjectCapabilityUsage.events([
            event("own"), event("foreign", room: "foreign"),
            event("other-provider", provider: "codex"),
            event("other-kind", kind: .skill), event("other-server", name: "slack"),
            event("remote", room: "remote", provider: "codex"),
        ], snapshot: snapshot(), rooms: ["mac": "local-mac", "workstation": "remote"],
            kind: .mcp, name: "github", endpointId: "mac", provider: "claude")
        XCTAssertEqual(rows.map(\.id), ["own"])
        XCTAssertEqual(rows.first?.effectiveOutcome, .unknown)
        XCTAssertNil(ProjectUsageStats.totals(rows)?.cpuTimeMs)
    }

    func testSkillNameMatchesRemainScopedToTheSelectedComputer() {
        let rows = ProjectCapabilityUsage.events([
            event("local", kind: .skill, name: "review"),
            event("remote", room: "remote", provider: "codex", kind: .skill, name: "review"),
        ], snapshot: snapshot(), rooms: ["mac": "local-mac", "workstation": "remote"],
            kind: .skill, name: "review", endpointId: "mac")
        XCTAssertEqual(rows.map(\.id), ["local"])
        XCTAssertTrue(ProjectCapabilityUsage.events(rows, snapshot: snapshot(), rooms: [:],
                                                   kind: .skill, name: "review").isEmpty)
    }

    func testCapabilityDetailsRetainReportedIdentityAndKeepMissingVersionUnknown() {
        let skill = ProjectCapabilityInfo.skill(.init(name: "review", endpointId: "mac",
            description: "Full description", version: "1", digest: "digest",
            source: "workspace", state: "discovered"))
        XCTAssertEqual(skill.description, "Full description")
        XCTAssertEqual(skill.fields.count, 5)
        XCTAssertEqual(ProjectCapabilityInfo.skill(.init(name: "review")).fields.count, 1)
        let server = ProjectCapabilityInfo.server(.init(name: "github", title: "GitHub",
            provider: "claude", endpointId: "mac", configuredEnabled: false, allowed: false,
            authStatus: "unknown", configDigest: "digest", sessionIds: ["same"]))
        XCTAssertEqual(server.title, "GitHub")
        XCTAssertEqual(server.fields.first(where: { $0.title == "Version" })?.value, "Not reported")
        XCTAssertEqual(server.fields.first(where: { $0.title == "Native configuration" })?.value, "Disabled")
    }

    func testCapabilityRowsOpenDetailsWithObservedAndUnknownMetrics() {
        let model = AppModel()
        let mesh = snapshot()
        model.meshSnapshots[mesh.projectId] = mesh
        model.meshComputerRoomByEndpointId = ["mac": "local-mac"]
        CapabilityUsageStore.shared.clear()
        defer { CapabilityUsageStore.shared.clear() }
        let server = ProjectCapabilityInfo.server(.init(name: "github", provider: "claude",
            endpointId: "mac", configuredEnabled: true, allowed: true, version: "2", sessionIds: []))
        RenderProbe.render(ProjectCapabilityDetailView(info: server, snapshot: mesh, model: model))
        for index in 0..<25 {
            CapabilityUsageStore.shared.record(.mcp, name: "github", sessionId: "same",
                sourceId: "call-\(index)", durationMs: index == 0 ? 100 : nil,
                outcome: index == 0 ? .error : nil, sourceNamespace: "local-mac", agent: "claude",
                resource: index == 0 ? .init(attribution: .measured, cpuTimeMs: 40, peakRssBytes: 1_024) : nil)
        }
        RenderProbe.render(ProjectCapabilityDetailView(info: server, snapshot: mesh, model: model))
        RenderProbe.render(ProjectCapabilityRow(info: server, snapshot: mesh, model: model))
        let skill = ProjectCapabilityInfo.skill(.init(name: "review", description: "Description"))
        RenderProbe.render(ProjectCapabilityDetailView(info: skill, snapshot: mesh, model: model))
        RenderProbe.render(ProjectCapabilityRow(info: skill, snapshot: mesh, model: model))
        RenderProbe.render(ProjectActionRulesView(project: mesh.project, model: model))
    }
}

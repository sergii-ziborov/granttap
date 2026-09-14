import SwiftUI
import XCTest
@testable import GrantTap

/// Every row a Governance screen can show, in every honest state, and the
/// screens around it: computers, bindings, and a Project with nothing in it.
@MainActor
final class ProjectGovernanceRowTests: XCTestCase {
    private let now = ProjectGovernanceViewFixtures.now

    func testProjectManagementDestinationsRenderWithAndWithoutGovernance() {
        let model = AppModel()
        let snapshot = ProjectGovernanceViewFixtures.projectSnapshot()
        model.projectGovernance[snapshot.projectId] = ProjectGovernanceViewFixtures.policyProjection()
        ProjectGovernanceViewFixtures.render(List { ProjectDestinationRows(snapshot: snapshot, model: model) })
        ProjectGovernanceViewFixtures.render(ProjectDestinationLabel(title: "Governance", detail: "2 rules", icon: "checkmark.shield"))
        ProjectGovernanceViewFixtures.render(ProjectGovernanceView(project: snapshot.project, model: model))
        model.projectGovernance = [:]
        ProjectGovernanceViewFixtures.render(ProjectGovernanceView(project: snapshot.project, model: model))
        ProjectGovernanceViewFixtures.render(ProjectMembersView(snapshot: snapshot, model: model))
        ProjectGovernanceViewFixtures.render(ProjectMeshStatusView(snapshot: snapshot, model: model))
    }

    func testPolicyRowsCoverEveryHonestEffectAndCoverageState() {
        for effect in ProjectPolicyEffect.allCases {
            let rule = ProjectPolicyRuleSummary(
                ruleId: effect.rawValue, effect: effect, capabilityKind: "mcp",
                displayName: nil, provider: "claude", origin: "catalog",
                fingerprintConfidence: "name_only"
            )
            let row = ProjectPolicyRuleRow(rule: rule)
            ProjectGovernanceViewFixtures.render(row.body)
            ProjectGovernanceViewFixtures.render(row)
            XCTAssertEqual(rule.id, effect.rawValue)
        }
        for status in ProjectPolicyCoverageStatus.allCases {
            let item = ProjectGovernanceViewFixtures.coverage("claude", "Shell", status)
            let row = ProjectPolicyCoverageRow(item: item)
            ProjectGovernanceViewFixtures.render(row.body)
            ProjectGovernanceViewFixtures.render(row)
            XCTAssertFalse(item.id.isEmpty)
        }
        XCTAssertEqual(ProjectGovernancePresentation.enforcementLabel(.strict), L("Strict"))
        XCTAssertEqual(
            ProjectGovernancePresentation.ruleTitle(.init(
                ruleId: "cli", effect: .allow, capabilityKind: "cli"
            )),
            "CLI"
        )
        let shell = ProjectPolicyRuleSummary(
            ruleId: "shell", effect: .allow, capabilityKind: "shell"
        )
        XCTAssertEqual(ProjectGovernancePresentation.ruleTitle(shell), "Shell")
        XCTAssertNil(ProjectGovernancePresentation.ruleDetail(shell))
    }

    func testComputerAndBindingRowsStayBoundedAndNeverRenderLocalPaths() {
        let available = ProjectComputerSummary(
            endpointId: "mac", displayName: "Review Mac", repositoryCount: 1, available: true
        )
        let unavailable = ProjectComputerSummary(
            endpointId: "pc", displayName: "Build PC", repositoryCount: 0, available: false
        )
        let availableRow = ProjectComputerRow(computer: available)
        let unavailableRow = ProjectComputerRow(computer: unavailable)
        ProjectGovernanceViewFixtures.render(availableRow.body)
        ProjectGovernanceViewFixtures.render(unavailableRow.body)
        ProjectGovernanceViewFixtures.render(availableRow)
        ProjectGovernanceViewFixtures.render(unavailableRow)
        XCTAssertEqual(available.id, "mac")
        XCTAssertTrue(available.detail.contains(L("Available")))
        XCTAssertTrue(unavailable.detail.contains(L("Unavailable")))

        let model = AppModel()
        let short = ProjectGovernanceViewFixtures.binding("short", "mac", "ios", "/Users/private/granttap")
        let long = ProjectGovernanceViewFixtures.binding(
            "long", "endpoint-with-a-long-private-identity", "runtime", "/private/runtime"
        )
        let shortRow = ProjectBindingRow(binding: short, model: model)
        let longRow = ProjectBindingRow(binding: long, model: model)
        ProjectGovernanceViewFixtures.render(shortRow.body)
        ProjectGovernanceViewFixtures.render(longRow.body)
        ProjectGovernanceViewFixtures.render(shortRow)
        ProjectGovernanceViewFixtures.render(longRow)
        XCTAssertEqual(short.id, "short")
        XCTAssertFalse(shortRow.detail.contains("/Users/private"))
        XCTAssertTrue(longRow.detail.hasPrefix(L("Computer")))
    }

    func testExecutionFallbackAndBindingOrderingCoverWeakProjectModes() {
        let original = ProjectGovernanceViewFixtures.projectSnapshot()
        let endpoint = "endpoint-with-a-long-private-identity"
        let execution = ExecutionSessionLink(
            taskId: "task", sessionId: "session", provider: "codex",
            computerId: endpoint, workspace: "/private/workspace",
            startedAt: now, endedAt: nil
        )
        let executionOnly = ProjectMeshSnapshot(
            type: original.type, sessionId: original.sessionId, projectId: original.projectId,
            project: original.project, bindings: nil, tasks: [], executions: [execution],
            claims: [], dependencies: [], events: [], generatedAt: original.generatedAt
        )
        let computers = ProjectMembersView(snapshot: executionOnly, model: AppModel()).computers
        XCTAssertEqual(computers.first?.repositoryCount, 0)
        XCTAssertEqual(computers.first?.available, true)
        XCTAssertTrue(computers.first?.displayName.hasPrefix(L("Computer")) == true)

        let sameName = ProjectMeshSnapshot(
            type: original.type, sessionId: original.sessionId, projectId: original.projectId,
            project: original.project,
            bindings: [
                ProjectGovernanceViewFixtures.binding("z", "mac", "z", "/private/z"),
                ProjectGovernanceViewFixtures.binding("a", "mac", "a", "/private/a"),
            ].map { value in
                .init(
                    bindingId: value.bindingId, projectId: value.projectId,
                    endpointId: value.endpointId, repositoryId: value.repositoryId,
                    displayName: "Same", available: false
                )
            },
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: now
        )
        let status = ProjectMeshStatusView(snapshot: sameName, model: AppModel())
        XCTAssertEqual(status.bindings.map(\.bindingId), ["a", "z"])
        XCTAssertFalse(ProjectMembersView(snapshot: sameName, model: AppModel())
            .computers.first?.available ?? true)
    }

    func testEmptyProjectAndSingleComputerSummariesRemainTruthful() {
        let original = ProjectGovernanceViewFixtures.projectSnapshot()
        let empty = ProjectMeshSnapshot(
            type: original.type, sessionId: original.sessionId, projectId: original.projectId,
            project: original.project, bindings: [], tasks: [], executions: [], claims: [],
            dependencies: [], events: [], generatedAt: original.generatedAt
        )
        XCTAssertEqual(ProjectManagePresentation.governanceSummary(nil), L("Not reported"))
        let computers = String(format: L("%d computers"), 0)
        XCTAssertEqual(
            ProjectManagePresentation.membersSummary(empty), "\(L("1 person")) · \(computers)"
        )
        XCTAssertEqual(
            ProjectManagePresentation.meshSummary(empty), "\(L("Private")) · \(computers)"
        )
        ProjectGovernanceViewFixtures.render(ProjectMembersView(snapshot: empty, model: AppModel()))
        ProjectGovernanceViewFixtures.render(ProjectMeshStatusView(snapshot: empty, model: AppModel()))
    }
}

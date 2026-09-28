import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ProjectGovernanceCustomTests: XCTestCase {
    /// The status the Mac's engine actually produces, nulls and all.
    private let macStatus = """
    {"type":"project.policy.status","sessionId":"project-R4uSndA","projectId":"project-R4uSndA","policy":{"projectId":"project-R4uSndA","revision":1,"enforcement":"best_available","rules":[{"ruleId":"granttap-default-agent","projectId":"project-R4uSndA","selector":{"kind":"agent","displayName":null,"origin":null,"fingerprint":null},"effect":"allow","conditions":{"endpointIds":[],"providers":[],"impact":null},"revision":1,"createdBy":"granttap-phone"},{"ruleId":"granttap-default-mcp","projectId":"project-R4uSndA","selector":{"kind":"mcp","displayName":null,"origin":null,"fingerprint":null},"effect":"allow","conditions":{"endpointIds":[],"providers":[],"impact":null},"revision":1,"createdBy":"granttap-phone"}]},"coverage":{"projectId":"project-R4uSndA","policyRevision":1,"enforcement":"best_available","requiredCapabilities":[],"endpoints":[{"projectId":"project-R4uSndA","policyRevision":1,"endpointId":"Mac.local","provider":"claude","capabilities":[{"kind":"agent","status":"unsupported"},{"kind":"mcp","status":"enforced"}],"observedAt":1788362800376}],"strictReady":true},"generatedAt":1788627682358}
    """

    func testAStatusWithNullsIsReadAsAStatusWithoutThem() throws {
        let data = Data(macStatus.utf8)
        XCTAssertTrue(ProjectGovernanceWireValidator.validStatus(data), "null is absent, not a wrong value")
        let status = try JSONDecoder().decode(ProjectPolicyStatus.self, from: data)
        let merged = try XCTUnwrap(ProjectGovernanceLogic.merged(current: nil, status: status))
        XCTAssertEqual(merged.rules.count, 2)
        XCTAssertEqual(merged.policy?.revision, 1)
        XCTAssertEqual(ProjectManagePresentation.governanceSummary(merged), String(format: L("%d rules"), 2))
        let stripped = ProjectGovernanceWireValidator.withoutNulls(["a": NSNull(), "b": ["c": NSNull(), "d": 1], "e": [NSNull(), 2]]) as? [String: Any]
        XCTAssertEqual(stripped?.keys.sorted(), ["b", "e"])
        XCTAssertEqual((stripped?["b"] as? [String: Any])?.keys.sorted(), ["d"])
        XCTAssertEqual((stripped?["e"] as? [Any])?.count, 1)
    }

    func testARefusalIsValidatedKeepsTheEditAndSaysWhy() throws {
        let json = """
        {"type":"project.policy.rejected","sessionId":"p","projectId":"p","expectedRevision":0,"currentRevision":1,"reason":"revision_mismatch","detail":"policy revision conflict","generatedAt":1788627682358}
        """
        XCTAssertTrue(ProjectGovernanceWireValidator.validRejected(Data(json.utf8)))
        XCTAssertFalse(ProjectGovernanceWireValidator.validRejected(Data(json.replacingOccurrences(of: "revision_mismatch", with: "because").utf8)))
        XCTAssertFalse(ProjectGovernanceWireValidator.validRejected(Data(json.replacingOccurrences(of: "\"detail\"", with: "\"extra\"").utf8)))
        let rejected = try JSONDecoder().decode(ProjectPolicyRejected.self, from: Data(json.utf8))

        let model = AppModel()
        model.agentMeshPreferences.meshEnabled = true
        let draft = ProjectGovernanceDraft(enforcement: .bestAvailable, defaults: [.shell: .allow],
                                           named: [.init(kind: .shell, name: "rm"): .deny])
        model.projectPolicyDrafts["p"] = draft
        model.pendingProjectPolicyRevisions["p"] = 1
        model.deliveredProjectPolicyRevisions["p"] = 1
        model.receive(rejected, fromRoom: "room")
        XCTAssertNil(model.pendingProjectPolicyRevisions["p"], "Save is open again")
        XCTAssertNil(model.deliveredProjectPolicyRevisions["p"])
        XCTAssertEqual(model.projectPolicyDrafts["p"], draft, "the edit is what the person wants; it stays")
        XCTAssertEqual(model.projectPolicyErrors["p"], AppModel.rejectionMessage(rejected))
        XCTAssertTrue(AppModel.rejectionMessage(rejected).contains("1"))
        for reason in ["revision_mismatch", "engine_unavailable", "invalid_policy", "unknown"] {
            let variant = ProjectPolicyRejected(type: "project.policy.rejected", sessionId: "p", projectId: "p",
                                                expectedRevision: 0, currentRevision: nil, reason: reason, detail: nil, generatedAt: 1)
            XCTAssertFalse(AppModel.rejectionMessage(variant).isEmpty)
        }
        // A phone with Mesh off ignores it.
        model.agentMeshPreferences.meshEnabled = false
        model.projectPolicyErrors["p"] = nil
        model.receive(rejected, fromRoom: "room")
        XCTAssertNil(model.projectPolicyErrors["p"])
        model.projectPolicyDrafts = [:]
    }

    func testAnEditSurvivesARelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("drafts-\(UUID().uuidString).json")
        let draft = ProjectGovernanceDraft(
            enforcement: .strict, defaults: [.shell: .allow, .deploy: .ask],
            named: [.init(kind: .shell, name: "rm"): .deny, .init(kind: .deploy, name: "git push"): .deny]
        )
        ProjectGovernanceDraftStore.save(["p": draft], to: url)
        XCTAssertEqual(ProjectGovernanceDraftStore.load(from: url), ["p": draft])
        ProjectGovernanceDraftStore.save([:], to: url)
        XCTAssertEqual(ProjectGovernanceDraftStore.load(from: url), [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "nothing pending, nothing kept")
    }

    func testCustomIsAChoiceInTheSamePickerAndLeavingItDropsTheRows() {
        var defaults: [ProjectCapabilityKind: ProjectPolicyEffect] = [.shell: .allow]
        var kinds: Set<ProjectCapabilityKind> = []
        var named: [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect] = [.init(kind: .shell, name: "rm"): .deny]
        XCTAssertEqual(ProjectGovernanceChoice.current(kind: .shell, defaults: defaults, customKinds: kinds), .effect(.allow))
        XCTAssertEqual(ProjectGovernanceChoice.current(kind: .mcp, defaults: defaults, customKinds: kinds), .inherit)
        ProjectGovernanceChoice.apply(.custom, kind: .shell, defaults: &defaults, customKinds: &kinds, named: &named)
        XCTAssertEqual(ProjectGovernanceChoice.current(kind: .shell, defaults: defaults, customKinds: kinds), .custom)
        XCTAssertEqual(defaults[.shell], .allow, "the default becomes the table's everything-else row")
        ProjectGovernanceChoice.apply(.effect(.deny), kind: .shell, defaults: &defaults, customKinds: &kinds, named: &named)
        XCTAssertEqual(defaults[.shell], .deny)
        XCTAssertTrue(named.isEmpty, "a row that is no longer shown must not go on applying")
        XCTAssertFalse(kinds.contains(.shell))
        ProjectGovernanceChoice.apply(.inherit, kind: .shell, defaults: &defaults, customKinds: &kinds, named: &named)
        XCTAssertNil(defaults[.shell])
        XCTAssertEqual(ProjectGovernanceChoice.all.map(\.label).count, 5)
    }

    func testACoAuthoredCommitIsARowOfItsOwn() {
        let rows = ProjectGovernanceCandidates.named(events: [], sessionIds: [], existing: [:], extra: ProjectGovernanceCandidates.builtIn)
        let row = ProjectGovernanceLogic.NamedRule(kind: .shell, name: ProjectGovernanceTable.coAuthorship)
        XCTAssertTrue(rows.contains(row))
        XCTAssertEqual(ProjectGovernanceTable.rowLabel(row), L("Commit or PR with a co-author or generated-with trailer"))
        XCTAssertEqual(ProjectGovernanceTable.rowLabel(.init(kind: .shell, name: "rm")), "rm")
        XCTAssertEqual(ProjectGovernanceTable.rowLabel(.init(kind: .mcp, name: "github")), MCPIdentity(name: "github").displayName)
        // The rule the Mac receives still targets the name, not the sentence.
        let policy = ProjectGovernanceLogic.updatedPolicy(
            current: nil, projectId: "p", enforcement: .bestAvailable, defaults: [.shell: .allow],
            named: [row: .deny], createdBy: "phone"
        )
        XCTAssertEqual(policy.rules.first { $0.selector.displayName == "co-authorship" }?.effect, .deny)
    }

    func testTheEditorAndTheCustomTablesRender() {
        var enforcement = ProjectEnforcementMode.bestAvailable
        var defaults: [ProjectCapabilityKind: ProjectPolicyEffect] = [.shell: .allow]
        var kinds: Set<ProjectCapabilityKind> = [.shell, .deploy]
        var named: [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect] = [.init(kind: .shell, name: "rm"): .deny]
        var custom: Set<ProjectGovernanceLogic.NamedRule> = []
        let candidates = ProjectGovernanceCandidates.named(events: [], sessionIds: [], existing: named, extra: ProjectGovernanceCandidates.builtIn)
        RenderProbe.render(
            List {
                ProjectGovernanceEditorSection(
                    enforcement: Binding(get: { enforcement }, set: { enforcement = $0 }),
                    defaults: Binding(get: { defaults }, set: { defaults = $0 }),
                    enabled: true,
                    customKinds: Binding(get: { kinds }, set: { kinds = $0 }),
                    named: Binding(get: { named }, set: { named = $0 })
                )
                ProjectGovernanceNamedSection(
                    candidates: candidates, named: Binding(get: { named }, set: { named = $0 }), enabled: true,
                    customNames: Binding(get: { custom }, set: { custom = $0 }),
                    customKinds: kinds, defaults: Binding(get: { defaults }, set: { defaults = $0 })
                )
            }
        )
        // Without the custom bindings the picker keeps its four answers.
        RenderProbe.render(
            List {
                ProjectGovernanceEditorSection(
                    enforcement: Binding(get: { enforcement }, set: { enforcement = $0 }),
                    defaults: Binding(get: { defaults }, set: { defaults = $0 }), enabled: false
                )
            }
        )
        XCTAssertEqual(ProjectGovernanceEditorSection.capabilityLabel(.mcp), "MCP")
    }
}

extension ProjectGovernanceCustomTests {
    func testCustomOpensASheetAndTheRowSaysWhatItHolds() {
        var defaults: [ProjectCapabilityKind: ProjectPolicyEffect] = [.shell: .allow]
        var kinds: Set<ProjectCapabilityKind> = [.shell]
        var named: [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect] = [.init(kind: .shell, name: "rm"): .deny]
        var custom: Set<ProjectGovernanceLogic.NamedRule> = []
        var enforcement = ProjectEnforcementMode.bestAvailable
        var opened: [ProjectCapabilityKind] = []
        XCTAssertEqual(
            ProjectGovernanceEditorSection.customSummary(.shell, named: named, defaults: defaults),
            String(format: L("%d rule"), 1) + " · " + String(format: L("rest: %@"), L("Allow"))
        )
        XCTAssertEqual(
            ProjectGovernanceEditorSection.customSummary(.deploy, named: named, defaults: defaults),
            String(format: L("%d rules"), 0) + " · " + String(format: L("rest: %@"), L("Inherit"))
        )
        RenderProbe.render(
            List {
                ProjectGovernanceEditorSection(
                    enforcement: Binding(get: { enforcement }, set: { enforcement = $0 }),
                    defaults: Binding(get: { defaults }, set: { defaults = $0 }),
                    enabled: true,
                    customKinds: Binding(get: { kinds }, set: { kinds = $0 }),
                    named: Binding(get: { named }, set: { named = $0 }),
                    onCustom: { opened.append($0) }
                )
            }
        )
        let candidates = ProjectGovernanceCandidates.named(events: [], sessionIds: [], existing: named, extra: ProjectGovernanceCandidates.builtIn)
        RenderProbe.render(
            ProjectGovernanceCustomSheet(
                kind: .shell, candidates: candidates,
                named: Binding(get: { named }, set: { named = $0 }),
                defaults: Binding(get: { defaults }, set: { defaults = $0 }),
                customNames: Binding(get: { custom }, set: { custom = $0 }),
                enabled: true
            )
        )
        XCTAssertTrue(opened.isEmpty, "rendering opens nothing; a tap does")
    }
}

extension ProjectGovernanceCustomTests {
    func testEnforcementFoldsToOneRowAndOpensIntoCoverageByComputer() {
        let rows = [
            ProjectPolicyCoverageSummary(endpointId: "Mac.lan", provider: "claude", capability: "shell", status: .enforced),
            ProjectPolicyCoverageSummary(endpointId: "Mac.lan", provider: "claude", capability: "agent", status: .unsupported),
            ProjectPolicyCoverageSummary(endpointId: "Mac.lan", provider: "grok", capability: "shell", status: .observed),
            ProjectPolicyCoverageSummary(endpointId: "Air.local", provider: "codex", capability: "mcp", status: .unknown),
        ]
        XCTAssertEqual(
            ProjectGovernancePresentation.coverageSummary(rows),
            "\(L("Enforced")) 1 · \(L("Observed only")) 1 · \(L("Unsupported")) 1 · \(L("Unknown")) 1"
        )
        XCTAssertEqual(ProjectGovernancePresentation.coverageSummary([]), L("No coverage reported yet."))
        for status in ProjectPolicyCoverageStatus.allCases {
            XCTAssertFalse(ProjectGovernancePresentation.coverageExplanation(status).isEmpty)
            _ = ProjectGovernancePresentation.coverageColor(status)
        }
        let governance = ProjectGovernanceProjection(
            projectId: "p", revision: 2, enforcement: .strict, rules: [], coverage: rows, updatedAt: 1,
            requiredCapabilities: [.shell], strictReady: false, policy: nil
        )
        XCTAssertEqual(ProjectGovernancePresentation.enforcementSummary(governance), String(format: L("%@ · revision %d"), L("Strict"), 2))
        let detail = ProjectEnforcementDetailView(governance: governance, coverage: rows)
        XCTAssertEqual(detail.byComputer.map(\.endpointId), ["Air.local", "Mac.lan"])
        XCTAssertEqual(detail.byComputer[1].rows.map(\.capability), ["agent", "shell", "shell"])
        RenderProbe.render(NavigationView { detail })
        RenderProbe.render(NavigationView { ProjectEnforcementDetailView(governance: governance, coverage: []) })
        RenderProbe.render(ProjectPolicyCoverageRow(item: rows[0], showsEndpoint: false))
    }
}

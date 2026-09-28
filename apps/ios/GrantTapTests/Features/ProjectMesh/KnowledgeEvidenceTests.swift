import XCTest
@testable import GrantTap

@MainActor
final class KnowledgeEvidenceTests: XCTestCase {
    private func snapshot() -> ProjectMeshSnapshot {
        let projectId = "mesh"
        let repositoryId = "github.com/owner/granttap"
        let capsule = TaskCapsule(
            taskId: "task", goal: "Repair the app", currentStatus: "working",
            sourceProvider: "codex", sourceComputer: "endpoint-a",
            targetProvider: "claude", targetComputer: "endpoint-b",
            repository: repositoryId, baseSha: String(repeating: "a", count: 40),
            latestCommit: String(repeating: "b", count: 40),
            filesChanged: ["apps/ios/App.swift"], dependencies: [],
            resourceClaims: [], remainingWork: ["Inspect next failure"],
            importantDecisions: ["Keep the existing Project identity"], createdAt: 10
        )
        return ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: projectId, projectId: projectId,
            project: .init(
                projectId: projectId, name: "granttap",
                canonicalRepositoryId: repositoryId, createdAt: 1
            ),
            bindings: [
                .init(bindingId: "a", projectId: projectId, endpointId: "endpoint-a",
                      repositoryId: repositoryId, displayName: "nodvox", available: true),
                .init(bindingId: "b", projectId: projectId, endpointId: "endpoint-b",
                      repositoryId: repositoryId, displayName: "nodvox", available: false),
            ],
            tasks: [.init(
                taskId: "task", projectId: projectId, title: "Repair",
                goal: "A raw chat instruction must not be called shared knowledge.",
                state: "working", ownerSessionId: "native", createdAt: 1, updatedAt: 10
            )],
            executions: [.init(
                taskId: "task", sessionId: "native", provider: "codex",
                computerId: "endpoint-a", workspace: "/repo",
                repositoryId: repositoryId, startedAt: 1
            )],
            claims: [], dependencies: [],
            events: [.init(
                type: "mesh.event", sessionId: "native", eventId: "handoff",
                projectId: projectId, taskId: "task", sourceSessionId: "native",
                eventType: "HANDOFF_REQUEST", createdAt: 10,
                payload: .init(capsule: capsule)
            )],
            generatedAt: 11
        )
    }

    func testKnowledgeLinksDecisionToExactTaskRepositoryAndCommit() {
        var project = snapshot()
        project.repositoryGraphs = [.init(
            projectId: "mesh", repositoryId: project.project.canonicalRepositoryId,
            revision: "graph-head", weavatrixVersion: "2.17.2",
            nodes: [], relations: [], totalNodes: 0, totalRelations: 0, truncated: false
        )]
        let summary = ProjectKnowledgePresentation.summary(snapshot: project, invocations: [])
        XCTAssertEqual(summary.decisions.map(\.text), ["Keep the existing Project identity"])
        XCTAssertEqual(summary.decisions.first?.taskId, "task")
        XCTAssertEqual(summary.decisions.first?.repositoryId, project.project.canonicalRepositoryId)
        XCTAssertEqual(summary.decisions.first?.commitSha, String(repeating: "b", count: 40))
        XCTAssertEqual(summary.decisions.first?.hasGraph, true)
        XCTAssertFalse(summary.decisions.contains {
            $0.text.contains("A raw chat instruction")
        })
        XCTAssertTrue(summary.packets.isEmpty)
    }

    func testDurableMemorySurvivesNewerSnapshotAndKeepsReportedSource() throws {
        var first = snapshot()
        first.knowledge = [ProjectKnowledgeRecord(
            projectId: "mesh", taskId: "task", recordId: "decision-1",
            category: "decision", content: "Keep the existing Project identity",
            source: "task_capsule", sourceRef: "handoff", visibility: "project",
            repositoryId: first.project.canonicalRepositoryId,
            commitSha: String(repeating: "b", count: 40), recordedAt: 10,
            streamVersion: 1
        )]
        var wire = first
        wire.events = [] // The legacy fixture's event scope is intentionally not wire-valid.
        XCTAssertTrue(ProjectMeshWireValidator.validSnapshot(try JSONEncoder().encode(wire)))
        let summary = ProjectKnowledgePresentation.summary(snapshot: first, invocations: [])
        XCTAssertEqual(summary.decisions.count, 1)
        XCTAssertEqual(summary.decisions.first?.source, L("Task capsule"))
        var newer = snapshot()
        newer.events = []
        let merged = ProjectMeshLogic.merged(current: first, incoming: newer, nowMs: 12)
        XCTAssertEqual(merged.knowledge?.map(\.recordId), ["decision-1"])
    }

    func testCorrectedDecisionStaysCurrentAfterStaleSnapshotRejoins() {
        var original = snapshot()
        original.knowledge = [ProjectKnowledgeRecord(
            projectId: "mesh", taskId: "task", recordId: "old",
            category: "decision", content: "Old rule", source: "task_capsule",
            sourceRef: "event-old", visibility: "project",
            repositoryId: original.project.canonicalRepositoryId,
            commitSha: nil, recordedAt: 10, streamVersion: 1
        )]
        var corrected = snapshot()
        var replacement = ProjectKnowledgeRecord(
            projectId: "mesh", taskId: "task", recordId: "new",
            category: "decision", content: "Reviewed rule", source: "user_decision",
            sourceRef: "event-new", visibility: "project",
            repositoryId: corrected.project.canonicalRepositoryId,
            commitSha: nil, recordedAt: 11, streamVersion: 2
        )
        replacement.supersedesRecordId = "old"
        corrected.knowledge = [replacement]
        let afterCorrection = ProjectMeshLogic.merged(
            current: original, incoming: corrected, nowMs: 12
        )
        let afterStale = ProjectMeshLogic.merged(
            current: afterCorrection, incoming: original, nowMs: 13
        )
        XCTAssertEqual(afterStale.knowledge?.map(\.recordId), ["new"])
    }

    func testCorrectedCapsuleDecisionDoesNotReturnFromOlderEvent() {
        let old = snapshot()
        var corrected = snapshot()
        var replacement = ProjectKnowledgeRecord(
            projectId: "mesh", taskId: "task", recordId: "reviewed",
            category: "decision", content: "Reviewed decision", source: "user_decision",
            sourceRef: "review", visibility: "project",
            repositoryId: corrected.project.canonicalRepositoryId,
            commitSha: nil, recordedAt: 12, streamVersion: 2
        )
        let oldId = "capsule-3a16eaa57832753ead3b66e0ed24c49822615cf8bf545b33dfca8762a3af0c95"
        replacement.supersedesRecordId = oldId
        corrected.knowledge = [replacement]
        corrected.supersededKnowledgeRecordIds = [oldId]
        let merged = ProjectMeshLogic.merged(current: corrected, incoming: old, nowMs: 13)
        let decisions = ProjectKnowledgePresentation.summary(snapshot: merged, invocations: []).decisions
        XCTAssertEqual(decisions.map(\.text), ["Reviewed decision"])
        XCTAssertEqual(merged.supersededKnowledgeRecordIds, [oldId])
    }

    func testCorrectionTombstoneHidesOldRecordAfterCorrectionLeavesBoundedPage() {
        var current = snapshot()
        current.events = []
        current.knowledge = (0..<16).map { index in
            ProjectKnowledgeRecord(
                projectId: "mesh", taskId: "task", recordId: "recent-\(index)",
                category: "decision", content: "Newer decision \(index)",
                source: "user_decision", sourceRef: "review-\(index)",
                visibility: "project", repositoryId: current.project.canonicalRepositoryId,
                commitSha: nil,
                recordedAt: Double(100 + index), streamVersion: index + 10
            )
        }
        current.supersededKnowledgeRecordIds = ["old"]
        var stale = snapshot()
        stale.events = []
        stale.knowledge = [ProjectKnowledgeRecord(
            projectId: "mesh", taskId: "task", recordId: "old",
            category: "decision", content: "Superseded decision",
            source: "task_capsule", sourceRef: "old-event", visibility: "project",
            repositoryId: stale.project.canonicalRepositoryId, commitSha: nil,
            recordedAt: 1, streamVersion: 1
        )]
        let merged = ProjectMeshLogic.merged(current: current, incoming: stale, nowMs: 120)
        XCTAssertFalse(merged.knowledge?.contains { $0.recordId == "old" } ?? true)
    }

    func testObservedRepositoryCommitAppearsOnceAcrossEndpointBindings() {
        var project = snapshot()
        let sha = String(repeating: "c", count: 40)
        project.bindings = [
            .init(bindingId: "a", projectId: "mesh", endpointId: "endpoint-a",
                  repositoryId: "github.com/owner/lad", displayName: "Lad",
                  available: true, revision: sha),
            .init(bindingId: "b", projectId: "mesh", endpointId: "endpoint-b",
                  repositoryId: "github.com/owner/lad", displayName: "Lad",
                  available: false, revision: sha),
            .init(bindingId: "virtual", projectId: "mesh", endpointId: "endpoint-a",
                  repositoryId: "local:/Users/me/dev", displayName: "dev", available: true),
        ]
        let revisions = ProjectKnowledgePresentation.summary(snapshot: project, invocations: []).revisions
        XCTAssertEqual(revisions.map(\.commitSha), [sha])
        XCTAssertEqual(revisions.first?.repositoryId, "github.com/owner/lad")
    }

    func testSameNamedComputersStaySeparateAndMissingUsageIsUnknown() {
        let project = snapshot()
        let computers = ProjectHealthDiagnostics.computers(project, connections: [])
        XCTAssertEqual(computers.map(\.id), ["endpoint-a", "endpoint-b"])
        XCTAssertNotEqual(computers[0].name, computers[1].name)
        XCTAssertEqual(computers.map(\.available), [true, false])
        XCTAssertNil(ProjectUsageStats.reportedTokens([], sessionIds: ["native"]))
        let session = SessionInfo(
            sessionId: "native", agent: "codex", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 42, tokensLastTurn: 1
        )
        XCTAssertEqual(ProjectUsageStats.reportedTokens([session], sessionIds: ["native"]), 42)
    }

    func testIndependentRepositoryGraphReportsSurviveTwoComputerSnapshots() {
        var first = snapshot()
        first.repositoryGraphs = [.init(
            projectId: "mesh", repositoryId: "github.com/owner/granttap",
            revision: "one", weavatrixVersion: "2.17.2", nodes: [], relations: [],
            totalNodes: 0, totalRelations: 0, truncated: false
        )]
        var second = snapshot()
        second.repositoryGraphs = [.init(
            projectId: "mesh", repositoryId: "github.com/owner/granttap-mcp",
            revision: "two", weavatrixVersion: "2.17.2", nodes: [], relations: [],
            totalNodes: 0, totalRelations: 0, truncated: false
        )]
        let merged = ProjectMeshLogic.merged(current: first, incoming: second, nowMs: 11)
        XCTAssertEqual(Set(merged.repositoryGraphs?.map(\.repositoryId) ?? []), [
            "github.com/owner/granttap", "github.com/owner/granttap-mcp"
        ])
    }
}

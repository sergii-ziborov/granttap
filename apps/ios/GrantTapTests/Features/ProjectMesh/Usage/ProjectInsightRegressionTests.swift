import XCTest
@testable import GrantTap

final class ProjectInsightRegressionTests: XCTestCase {
    func testGraphBuildWaitsForAFreshReportThenFinishesEvenOnFailure() {
        let request = ProjectGraphRequest(createdAt: 10)
        var old = snapshot(at: 9)
        XCTAssertTrue(request.receiving(old).pending, "plain Mesh updates do not confirm analysis")
        old.repositoryGraphs = [report(status: "COMPLETE", nodes: 4)]
        XCTAssertTrue(request.receiving(old).pending, "old reports cannot confirm a new build")
        var fresh = snapshot(at: 11)
        fresh.repositoryGraphs = old.repositoryGraphs
        fresh.graphAnalysisRequestId = request.requestId
        let completed = request.receiving(fresh)
        XCTAssertFalse(completed.pending)
        XCTAssertEqual(completed.result, .completed)
        fresh.repositoryGraphs = [report(status: "UNAVAILABLE", nodes: 0)]
        XCTAssertEqual(request.receiving(fresh).result, .failed)
        XCTAssertFalse(request.receiving(fresh).pending)
        XCTAssertEqual(completed.receiving(fresh), completed)
    }

    func testRoutineGraphSnapshotCannotConfirmAnExplicitRebuild() {
        let request = ProjectGraphRequest(createdAt: 0)
        var update = snapshot()
        update.repositoryGraphs = [report(status: "COMPLETE", nodes: 4)]
        XCTAssertTrue(request.receiving(update).pending,
            "a routine publication of a cached report is not a rebuild acknowledgement")
    }

    func testMissingOrChangedArchitectureRequiresAutomaticBuild() {
        var mesh = snapshot()
        XCTAssertFalse(ProjectInsightReports.needsAnalysis(mesh))
        mesh.bindings = [.init(bindingId: "bound", projectId: "p", endpointId: "mac", repositoryId: "repo",
            displayName: "Repository", available: true, revision: "sha")]
        XCTAssertTrue(ProjectInsightReports.needsAnalysis(mesh))
        mesh.repositoryGraphs = [report(status: "COMPLETE", nodes: 4)]
        XCTAssertFalse(ProjectInsightReports.needsAnalysis(mesh))
        mesh.bindings?[0].revision = "changed"
        XCTAssertTrue(ProjectInsightReports.needsAnalysis(mesh))
        mesh.bindings = [.init(bindingId: "bound", projectId: "p", endpointId: "mac", repositoryId: "repo",
            displayName: "Repository", available: false, revision: "changed")]
        XCTAssertFalse(ProjectInsightReports.needsAnalysis(mesh))
    }

    @MainActor
    func testAutomaticGraphRequestCoalescesAndEndsWhenNoRouteIsAvailable() async {
        let model = AppModel()
        model.relaysByRoom = [:]
        model.meshProjectSourceRooms = [:]
        model.meshSnapshots = ["p": snapshot()]
        let absent = await model.requestProjectGraphAnalysis(projectId: "absent")
        XCTAssertEqual(absent, .noRoute)
        let missingRoute = await model.requestProjectGraphAnalysis(projectId: "p")
        XCTAssertEqual(missingRoute, .noRoute)
        XCTAssertFalse(model.projectGraphRequests["p"]?.pending ?? true)
        model.projectGraphRequests["p"] = .init(createdAt: 1)
        let coalesced = await model.requestProjectGraphAnalysis(projectId: "p")
        XCTAssertEqual(coalesced, .requested)
        model.projectGraphRequests = [:]
        model.projectGraphAttemptAt = [:]
        var mesh = snapshot()
        mesh.bindings = [.init(bindingId: "bound", projectId: "p", endpointId: "mac", repositoryId: "repo",
            displayName: "Repository", available: true, revision: "sha")]
        model.meshSnapshots = ["p": mesh]
        model.ensureProjectGraphAnalysis(projectId: "p")
        for _ in 0..<50 { await Task.yield() }
        XCTAssertNotNil(model.projectGraphAttemptAt["p"])
        XCTAssertEqual(model.projectGraphRequests["p"]?.result, .noRoute)
        model.ensureProjectGraphAnalysis(projectId: "p")
        XCTAssertFalse(model.projectGraphRequests["p"]?.pending ?? true)
    }

    func testRepeatedRepositoryReportsAreCountedOnceAndACompleteReportWins() {
        var mesh = snapshot()
        let complete = report(status: "COMPLETE", nodes: 4)
        mesh.repositoryGraphs = [report(status: "UNAVAILABLE", nodes: 0), complete, complete]
        XCTAssertEqual(ProjectHealthDiagnostics.graphReport(for: "repo", snapshot: mesh), complete)
        XCTAssertEqual(ProjectMeshStatistics.make(mesh).graphNodes, 4)
    }

    func testConfirmedAnalysisPrecedesFailuresOfOlderRepositoryAliases() {
        var mesh = snapshot()
        let valid = report(status: "COMPLETE", nodes: 4)
        let old = ProjectRepositoryGraph(projectId: "p", repositoryId: "a-old-origin", revision: "old",
            weavatrixVersion: "unknown", analysisStatus: "UNAVAILABLE",
            analysisErrorCode: "REPOSITORY_IDENTITY_MISMATCH", nodes: [], relations: [],
            totalNodes: 0, totalRelations: 0, truncated: false)
        mesh.repositoryGraphs = [old, valid]
        XCTAssertEqual(ProjectInsightReports.reports(mesh), [valid, old],
                       "the Statistics summary must describe the confirmed analysis first")
    }

    func testDistinctOriginsAndCurrentRevisionArePreserved() {
        var mesh = snapshot()
        let current = ProjectRepositoryGraph(projectId: "p", repositoryId: "repo", revision: "new-sha",
            weavatrixVersion: "2.17.4", analysisStatus: "COMPLETE", nodes: [], relations: [],
            totalNodes: 4, totalRelations: 0, truncated: false)
        mesh.bindings = [.init(bindingId: "b", projectId: "p", endpointId: "mac",
                               repositoryId: "repo", displayName: "Repo", available: true, revision: "new-sha")]
        let other = ProjectRepositoryGraph(projectId: "p", repositoryId: "fork/repo", revision: "sha",
            weavatrixVersion: "2.17.4", analysisStatus: "COMPLETE", nodes: [], relations: [],
            totalNodes: 2, totalRelations: 0, truncated: false)
        mesh.repositoryGraphs = [current, report(status: "COMPLETE", nodes: 99), other]
        XCTAssertEqual(ProjectInsightReports.reports(mesh).count, 2)
        XCTAssertEqual(ProjectMeshStatistics.make(mesh).graphNodes, 6)
        XCTAssertTrue(ProjectInsightReports.hasEvidence(mesh))
        mesh.repositoryGraphs = [report(status: "UNAVAILABLE", nodes: 0)]
        XCTAssertFalse(ProjectInsightReports.hasEvidence(mesh))
    }

    func testCatalogRetainsGraphWithoutCortexAndDropsItWhenBindingsChange() {
        var old = snapshot()
        old.publisherEndpointId = "mac"
        old.repositoryGraphs = [report(status: "COMPLETE", nodes: 4)]
        var fresh = snapshot()
        XCTAssertEqual(ProjectInsightReports.retainingEnrichment(fresh, from: old).repositoryGraphs,
                       old.repositoryGraphs)
        fresh.repositoryGraphs = []
        XCTAssertEqual(ProjectInsightReports.retainingEnrichment(fresh, from: old).repositoryGraphs, [])
        fresh.repositoryGraphs = nil
        fresh.bindings = [.init(bindingId: "changed", projectId: "p", endpointId: "mac",
                                 repositoryId: "new-repo", displayName: "New", available: true)]
        XCTAssertNil(ProjectInsightReports.retainingEnrichment(fresh, from: old).repositoryGraphs)
        XCTAssertNil(ProjectInsightReports.retainingEnrichment(fresh, from: nil).repositoryGraphs)
    }

    func testStatisticsFollowTheExactLiveChatAndPreserveTerminalTaskState() {
        var mesh = snapshot()
        mesh.tasks = [.init(taskId: "t", projectId: "p", title: "Task", goal: "Goal", state: "planned",
                            ownerSessionId: "s", createdAt: 1, updatedAt: 2)]
        mesh.executions = [.init(taskId: "t", sessionId: "s", provider: "codex", computerId: "mac",
                                 workspace: "/repo", startedAt: 1)]
        let live = session(computer: "mac", state: "working", at: 10)
        let foreign = session(computer: "other", state: "waiting", at: 20)
        let old = session(computer: "mac", state: "idle", at: 3)
        var shown = ProjectMeshStatistics.presented(mesh, sessions: [foreign, old, live])
        XCTAssertEqual(shown.tasks.first?.state, "working")
        XCTAssertEqual(ProjectMeshStatistics.make(shown).activeTasks, 1)
        shown = ProjectMeshStatistics.presented(mesh, sessions: [foreign])
        XCTAssertEqual(shown.tasks.first?.state, "planned")
        mesh.tasks[0].state = "completed"
        XCTAssertEqual(ProjectMeshStatistics.presented(mesh, sessions: [live]).tasks[0].state, "completed")
    }

    @MainActor
    func testLocalAndRemoteRefreshRoutesAndFailureMessages() async {
        var localCalls = 0
        var rooms: [String] = []
        let local = ProjectGraphRefreshPlan.make(localProjectAvailable: true,
            sourceRooms: ["self"], connectedRooms: ["self"], localRoom: "self")
        let completed = await local.execute(localRefresh: { localCalls += 1; return true },
                                            remoteRefresh: { rooms.append($0) })
        XCTAssertEqual(completed, .completed)
        XCTAssertEqual(localCalls, 1)
        XCTAssertEqual(rooms, [])
        let remote = ProjectGraphRefreshPlan.make(localProjectAvailable: false,
            sourceRooms: ["phone", "offline"], connectedRooms: ["phone"])
        let requested = await remote.execute(localRefresh: { XCTFail("No local route"); return false },
                                               remoteRefresh: { rooms.append($0) })
        XCTAssertEqual(requested, .requested)
        XCTAssertEqual(rooms, ["phone"])
        let empty = ProjectGraphRefreshPlan(local: false, rooms: [])
        let noRoute = await empty.execute(localRefresh: { XCTFail(); return true },
                                          remoteRefresh: { _ in XCTFail() })
        XCTAssertEqual(noRoute, .noRoute)
        let partial = await ProjectGraphRefreshPlan(local: true, rooms: ["remote"]).execute(
            localRefresh: { true }, remoteRefresh: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertEqual(partial, .partial)
        let failed = await local.execute(localRefresh: { false }, remoteRefresh: { _ in })
        XCTAssertEqual(failed, .failed)
        let thrown = await local.execute(localRefresh: { throw URLError(.timedOut) }, remoteRefresh: { _ in })
        XCTAssertEqual(thrown, .failed)
        XCTAssertNotEqual(failed.message, noRoute.message)
    }

    func testLocalProcessSamplePreservesChatAttributionAndRejectsInvalidReadings() throws {
        let sample = Data(#"{"operation":"desktop.machine_load","source":"process_sample","computer":"mac","observed_at":100,"agents":[{"agent":"codex","processes":2,"cpu_percent":150,"memory_bytes":2048,"groups":[],"chats":[{"sessionId":"s","processes":1,"cpuPercent":120,"memoryBytes":1024}]}]}"#.utf8)
        let load = try JSONDecoder().decode(MacLocalMachineLoad.self, from: sample)
        XCTAssertTrue(load.isValid)
        XCTAssertEqual(load.wireLoad.agents[0].chats[0].sessionId, "s")
        XCTAssertEqual(load.wireLoad.agents[0].cpuPercent, 150)
        let invalid = Data(String(decoding: sample, as: UTF8.self).replacingOccurrences(
            of: "\"memory_bytes\":2048", with: "\"memory_bytes\":-1").utf8)
        XCTAssertFalse(try JSONDecoder().decode(MacLocalMachineLoad.self, from: invalid).isValid)
        let legacy = Data(String(decoding: sample, as: UTF8.self).replacingOccurrences(
            of: ",\"chats\":[{\"sessionId\":\"s\",\"processes\":1,\"cpuPercent\":120,\"memoryBytes\":1024}]", with: "").utf8)
        XCTAssertTrue(try JSONDecoder().decode(MacLocalMachineLoad.self, from: legacy).isValid)
    }

    func testCachedUsageEnrichesLiveChatsWithoutReplacingFresherNativeTotals() {
        var live = session(computer: "mac", state: "working", at: 10)
        let usage = SessionUsageSnapshot(sessionId: "s", agent: "codex", tokensSession: 12,
                                          tokensLastTurn: 3)
        XCTAssertEqual(usage.applyingIfMoreComplete(to: live).tokensSession, 12)
        live.tokensSession = 20
        XCTAssertEqual(usage.applyingIfMoreComplete(to: live).tokensSession, 20)
    }

    private func session(computer: String, state: String, at: Double) -> SessionInfo {
        .init(sessionId: "s", agent: "codex", projectId: "p", taskId: "t", computerId: computer,
              state: state, startedAt: 1, lastActivityAt: at, tokensSession: 0, tokensLastTurn: 0)
    }

    private func snapshot(at: Double = 1) -> ProjectMeshSnapshot {
        .init(type: "mesh.snapshot", sessionId: "p", projectId: "p",
              project: .init(projectId: "p", name: "Repository", canonicalRepositoryId: "repo", createdAt: 1),
              tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: at)
    }

    private func report(status: String, nodes: Int) -> ProjectRepositoryGraph {
        .init(projectId: "p", repositoryId: "repo", revision: "sha", weavatrixVersion: "2.17.4",
              analysisStatus: status, nodes: [], relations: [], totalNodes: nodes,
              totalRelations: 0, truncated: false)
    }
}

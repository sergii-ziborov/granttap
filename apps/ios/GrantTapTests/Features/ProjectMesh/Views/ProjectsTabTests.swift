import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ProjectsTabTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    override func setUp() {
        super.setUp()
        ProjectMeshPersistence.clear()
        ProjectPreferencesStore.save([:])
        ProjectCapabilityRequestStore.save([:])
    }

    override func tearDown() {
        ProjectPreferencesStore.save([:])
        ProjectCapabilityRequestStore.save([:])
        ProjectMeshPersistence.clear()
        super.tearDown()
    }

    private func snapshot(_ id: String, name: String, repo: String, working: Bool, at: Double) -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: id, projectId: id,
            project: .init(projectId: id, name: name, repositoryRoot: "/dev/\(name)", canonicalRepositoryId: repo, createdAt: 1),
            tasks: [
                .init(taskId: "\(id)-t1", projectId: id, title: "Task one", goal: "g", state: "working", ownerSessionId: "\(id)-s1", createdAt: 1, updatedAt: at),
                .init(taskId: "\(id)-t2", projectId: id, title: "Task two", goal: "g", state: "blocked", ownerSessionId: nil, createdAt: 1, updatedAt: at - 1_000),
                .init(taskId: "\(id)-t3", projectId: id, title: "Done", goal: "g", state: "completed", ownerSessionId: nil, createdAt: 1, updatedAt: 1),
            ],
            executions: [.init(taskId: "\(id)-t1", sessionId: "\(id)-s1", provider: "claude", computerId: "Mac.lan", workspace: "/dev/\(name)",
                               activeAt: working ? at : at - 3_600_000, startedAt: 1)],
            claims: [], dependencies: [], events: [], generatedAt: at
        )
    }

    private func session(_ id: String, working: Bool, at: Double) -> SessionInfo {
        SessionInfo(sessionId: id, agent: "claude", state: working ? "working" : "idle", startedAt: 1, lastActivityAt: at, tokensSession: 1, tokensLastTurn: 1)
    }

    func testTheListReadsBusiestFirstWithHiddenProjectsLast() {
        let busy = snapshot("p-busy", name: "nodvox", repo: "github.com/x/nodvox", working: true, at: now - 10_000)
        let quiet = snapshot("p-quiet", name: "granttap-mcp", repo: "github.com/x/granttap-mcp", working: false, at: now - 60_000)
        let old = snapshot("p-old", name: "nodvox", repo: "github.com/x/nodvox-old", working: false, at: now - 5 * 86_400_000)
        let rows = ProjectsCatalog.rows(
            snapshots: [old, quiet, busy], sessions: [session("p-busy-s1", working: true, at: now - 10_000)],
            preferences: ["p-old": ProjectPreference(customName: "Old copy", hidden: true), "p-quiet": ProjectPreference(customName: "  Runtime  ")],
            memberLinks: [], rooms: ["p-busy": ["room-a"]], now: now
        )
        XCTAssertEqual(rows.map(\.projectId), ["p-busy", "p-quiet", "p-old"])
        XCTAssertEqual(rows[0].working, 1)
        XCTAssertEqual(rows[0].needsYou, 1, "a blocked Task needs the person")
        XCTAssertEqual(rows[0].openTasks, 2, "the finished one is not open")
        XCTAssertEqual(rows[0].computers, 1)
        XCTAssertTrue(rows[0].holdsKey)
        XCTAssertFalse(rows[1].holdsKey)
        XCTAssertEqual(rows[1].name, "Runtime", "the person's name, trimmed")
        XCTAssertEqual(rows[1].repositoryLeaf, "granttap-mcp")
        XCTAssertTrue(rows[1].detail.contains("granttap-mcp"), rows[1].detail)
        XCTAssertFalse(rows[0].detail.contains("nodvox ·"), "the repository is not repeated when it is the name")
        XCTAssertTrue(rows[2].hidden)
        XCTAssertEqual(rows[2].name, "Old copy")
        XCTAssertEqual(ProjectsCatalog.displayName(old, preference: ProjectPreference(customName: " ")), "nodvox-old", "blank uses the repository name")
    }

    func testTwoRepositoryProjectsSharingACheckoutNameKeepDistinctRows() {
        let publicProject = snapshot("public", name: "nodvox", repo: "github.com/sergii-ziborov/granttap", working: true, at: now)
        let internalProject = snapshot("internal", name: "nodvox", repo: "github.com/sergii-ziborov/granttap-internal", working: false, at: now)
        let rows = ProjectsCatalog.rows(
            snapshots: [publicProject, internalProject], sessions: [], preferences: [:],
            memberLinks: [], rooms: [:], now: now
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: rows.map { ($0.projectId, $0.name) }), [
            "public": "granttap", "internal": "granttap-internal"
        ])
    }

    func testEmptyLegacyIdentityDoesNotMakeASecondRepositoryProject() {
        let active = snapshot("current", name: "nodvox", repo: "github.com/x/nodvox", working: true, at: now)
        var legacy = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "legacy", projectId: "legacy",
            project: .init(projectId: "legacy", name: "nodvox",
                           repositoryRoot: "-dev-nodvox", canonicalRepositoryId: "local:dev-nodvox",
                           createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: now - 1
        )
        let rooms: [String: Set<String>] = ["current": ["mac-a"], "legacy": ["mac-a"]]
        XCTAssertEqual(ProjectsCatalog.rows(
            snapshots: [legacy, active], sessions: [], preferences: [:],
            memberLinks: [], rooms: rooms
        ).map(\.projectId), ["current"])
        XCTAssertEqual(ProjectsCatalog.rows(
            snapshots: [legacy, active], sessions: [], preferences: [:],
            memberLinks: [], rooms: [:], localProjectIds: ["current", "legacy"]
        ).map(\.projectId), ["current"], "a local Mac has one owner even without relay rooms")

        legacy.tasks = active.tasks
        XCTAssertEqual(ProjectsCatalog.rows(
            snapshots: [legacy, active], sessions: [], preferences: [:],
            memberLinks: [], rooms: rooms
        ).count, 2, "A project with work is never hidden as a duplicate")
    }

    func testRenamingHidingAndForgettingAreThePhonesOwn() throws {
        let model = AppModel()
        let busy = snapshot("p-busy", name: "nodvox", repo: "github.com/x/nodvox", working: true, at: now - 10_000)
        let old = snapshot("p-old", name: "nodvox", repo: "github.com/x/nodvox-old", working: false, at: now - 86_400_000)
        model.meshSnapshots = ["p-busy": busy, "p-old": old]
        model.sessions = [session("p-busy-s1", working: true, at: now - 10_000)]
        model.meshProjectSourceRooms = ["p-old": ["room-b"]]
        model.pendingMeshEvents = [ProjectMeshEvent(type: "mesh.event", sessionId: "p-old-t1", eventId: "e-old", projectId: "p-old", taskId: "p-old-t1",
                                                     sourceSessionId: "p-old-s1", eventType: "TASK_BLOCKED", createdAt: now, payload: .init(reason: "x"))]
        model.meshAttentionStates = ["e-old": .init(status: .pending)]

        model.renameProject("p-old", to: "  Old copy ")
        XCTAssertEqual(model.projectDisplayName(id: "p-old"), "Old copy")
        XCTAssertEqual(model.projectDisplayName(id: "p-busy"), "nodvox")
        XCTAssertEqual(model.projectListRows.first { $0.projectId == "p-old" }?.name, "Old copy")
        model.renameProject("p-old", to: "")
        XCTAssertEqual(model.projectDisplayName(id: "p-old"), "nodvox-old", "an empty name gives the repository's back")
        XCTAssertNil(model.projectDisplayName(id: "nowhere"))

        model.setProjectHidden("p-old", true, now: now)
        XCTAssertTrue(model.isProjectHidden("p-old"))
        XCTAssertEqual(model.projectPreferences["p-old"]?.hiddenAt, now)
        let items = TaskListCatalog.items(model: model, sessions: model.sessions)
        XCTAssertFalse(items.contains { $0.projectId == "p-old" }, "a hidden Project's Tasks leave the list")
        XCTAssertTrue(items.contains { $0.projectId == "p-busy" })
        model.renameProject("p-busy", to: "Phone app")
        XCTAssertEqual(TaskListCatalog.items(model: model, sessions: model.sessions).first { $0.projectId == "p-busy" }?.projectName, "Phone app")
        XCTAssertEqual(ProjectPreferencesStore.load()["p-busy"]?.customName, "Phone app", "kept across launches")
        model.setProjectHidden("p-old", false)
        XCTAssertFalse(model.isProjectHidden("p-old"))
        XCTAssertNil(model.projectPreferences["p-old"]?.hiddenAt)

        model.forgetProject("p-old")
        XCTAssertNil(model.meshSnapshots["p-old"])
        XCTAssertTrue(model.pendingMeshEvents.isEmpty)
        XCTAssertNil(model.meshAttentionStates["e-old"])
        XCTAssertNil(model.meshProjectSourceRooms["p-old"])
        XCTAssertNil(model.projectPreferences["p-old"])
        XCTAssertNotNil(model.meshSnapshots["p-busy"], "only the forgotten Project goes")
        XCTAssertEqual(model.projectListRows.map(\.projectId), ["p-busy"])

        let report = model.report(for: .project(busy))
        XCTAssertEqual(report.title, "Phone app", "a report carries the phone's name for the Project")
        XCTAssertEqual(ReportBuilder.subtitle(for: .task(busy, busy.tasks[0]), computerName: { $0 }, projectName: { _ in "Phone app" }), "\(L("Task report")) · Phone app")
    }

    func testTheTabAndItsSheetsRender() {
        let model = AppModel()
        RenderProbe.render(NavigationView { ProjectsTabView(model: model) })
        let busy = snapshot("p-busy", name: "nodvox", repo: "github.com/x/nodvox", working: true, at: now - 10_000)
        let old = snapshot("p-old", name: "nodvox", repo: "github.com/x/nodvox-old", working: false, at: now - 86_400_000)
        model.meshSnapshots = ["p-busy": busy, "p-old": old]
        model.sessions = [session("p-busy-s1", working: true, at: now - 10_000)]
        model.setProjectHidden("p-old", true)
        RenderProbe.render(NavigationView { ProjectsTabView(model: model, showHidden: true) })
        RenderProbe.render(NavigationView { ProjectsTabView(model: model) })
        let row = model.projectListRows[0]
        RenderProbe.render(ProjectListRowView(row: row))
        RenderProbe.render(RenameProjectSheet(row: row, model: model))
        model.renameProject("p-busy", to: "Phone app")
        RenderProbe.render(RenameProjectSheet(row: model.projectListRows[0], model: model))
        RenderProbe.render(ContentView(selectedTab: .projects, modelOverride: model).environmentObject(model))

        let suite = UserDefaults(suiteName: "granttap.tests.projects.\(UUID().uuidString)")!
        ProjectPreferencesStore.save(["a": ProjectPreference(customName: "A"), "b": ProjectPreference()], defaults: suite)
        XCTAssertEqual(ProjectPreferencesStore.load(defaults: suite).keys.sorted(), ["a"], "an empty preference is not kept")
        ProjectPreferencesStore.save([:], defaults: suite)
        XCTAssertTrue(ProjectPreferencesStore.load(defaults: suite).isEmpty)
    }

    func testRecoveredProjectManagementScreensRenderFromOneProject() {
        let model = AppModel()
        var project = snapshot("project-management", name: "GrantTap", repo: "github.com/x/granttap",
                               working: true, at: now)
        project.skills = [ProjectSharedSkill(name: "Review", version: "1", state: "available")]
        project.mcpServers = [ProjectMcpServer(
            name: "Repository", provider: "claude", endpointId: "Mac.lan",
            configuredEnabled: true, allowed: true, version: "2.17.2",
            metadataSource: "mcp", sessionIds: ["project-management-s1"]
        )]
        project.modelCatalog = [ProjectEndpointModelCatalog(
            endpointId: "Mac.lan", observedAt: now,
            models: [ProjectAdvertisedModel(
                modelId: "model-1", provider: "claude", endpointId: "Mac.lan",
                source: "advertised", observedAt: now
            )]
        )]
        project.capabilityRequests = [ProjectCapabilityRequest(
            projectId: project.projectId, requestId: "build-request",
            kind: .skill, name: "Build", requestedAt: now
        )]
        project.capabilityObservations = [ProjectCapabilityObservation(
            projectId: project.projectId, requestId: "build-request", endpointId: "Mac.lan",
            state: "discovered", artifactDigest: String(repeating: "a", count: 64),
            observedAt: now
        )]
        let cortex = ProjectCortexIntegration(
            projectId: project.projectId, endpointId: "Mac.lan", enabled: true,
            maxTokens: 4096, state: "succeeded", version: "0.3.2", revision: "test-revision",
            weavatrixVersion: "2.17.0", packet: ProjectCortexPacketStatus(
                included: 5, omitted: 1, rawEstimatedTokens: 2000,
                selectedEstimatedTokens: 1000, omittedEstimatedTokens: 1000,
                deduplicatedLines: 2, requiresUpstream: true
            ), detail: "Expanded on request", checkedAt: now
        )
        project.cortex = [cortex]
        model.meshSnapshots[project.projectId] = project
        RenderProbe.render(NavigationView { ProjectCapabilitiesView(snapshot: project, model: model) })
        RenderProbe.render(NavigationView { ProjectCapabilityAddSheet(snapshot: project, model: model) })
        RenderProbe.render(NavigationView { ProjectExecutionView(snapshot: project, model: model) })
        RenderProbe.render(NavigationView { ProjectNewTaskView(snapshot: project, model: model) })
        RenderProbe.render(NavigationView { ProjectCortexView(snapshot: project, model: model) })
        RenderProbe.render(NavigationView { ProjectCortexEndpointView(
            projectId: cortex.projectId, endpointId: cortex.endpointId,
            integration: cortex, model: model
        ) })
        RenderProbe.render(NavigationView { ProjectCortexEndpointView(
            projectId: cortex.projectId, endpointId: cortex.endpointId,
            integration: nil, model: model
        ) })
        RenderProbe.render(NavigationView { ProjectEnvironmentView(snapshot: project, model: model) })
        RenderProbe.render(NavigationView { ProjectRestrictionsView(snapshot: project, model: model) })
        RenderProbe.render(NavigationView { ProjectKnowledgeView(snapshot: project, model: model) })
        RenderProbe.render(NavigationView { ProjectMeshStatisticsView(snapshot: project, model: model) })
        RenderProbe.render(NavigationView { ProjectStatisticsTasksView(snapshot: project, model: model) })
        RenderProbe.render(NavigationView { ProjectStatisticsActivityView(snapshot: project, model: model) })
        RenderProbe.render(NavigationView { ProjectStatisticsUsageView(snapshot: project, model: model) })
        RenderProbe.render(NavigationView { ProjectUsageEventsView(events: [], title: "Task history") })
        RenderProbe.render(NavigationView {
            ProjectCapabilityRequestDetailView(request: project.capabilityRequests![0],
                                               snapshot: project, model: model)
        })
        let computer = ProjectComputerSummary(
            endpointId: "Mac.lan", displayName: "Office Mac", repositoryCount: 1, available: true
        )
        RenderProbe.render(NavigationView {
            ProjectComputerAccessView(snapshot: project, computer: computer, model: model)
        })
    }

    func testCapabilityRequestIsScopedAndDeduplicatedWithinProject() {
        let model = AppModel()
        let project = snapshot("capability-project", name: "GrantTap", repo: "github.com/x/granttap",
                               working: false, at: now)
        model.meshSnapshots[project.projectId] = project
        model.requestProjectCapability(projectId: "other-project", kind: .mcp,
                                       name: "Repository", source: nil, version: nil)
        XCTAssertTrue(model.requestedProjectCapabilities.isEmpty)
        model.requestProjectCapability(projectId: project.projectId, kind: .mcp,
                                       name: "  Repository  ", source: "  local  ", version: "  1  ")
        model.requestProjectCapability(projectId: project.projectId, kind: .mcp,
                                       name: "repository", source: nil, version: nil)
        let requests = model.requestedProjectCapabilities[project.projectId] ?? []
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.name, "repository")
        XCTAssertNil(requests.first?.source)
        XCTAssertNil(requests.first?.version)
    }

    func testMcpWireVersionKeepsDifferentImplementationsAsDifferentRows() throws {
        let data = Data(#"{"name":"weavatrix","provider":"codex","endpointId":"mac-a","configuredEnabled":true,"allowed":false,"version":"2.17.2","metadataSource":"mcp","sessionIds":["native-a"]}"#.utf8)
        let server = try JSONDecoder().decode(ProjectMcpServer.self, from: data)
        XCTAssertEqual(server.version, "2.17.2")
        XCTAssertEqual(server.metadataSource, "mcp")
        var changed = server
        changed.version = "2.18.0"
        XCTAssertNotEqual(server.id, changed.id)
        XCTAssertFalse(server.allowed)
    }
}

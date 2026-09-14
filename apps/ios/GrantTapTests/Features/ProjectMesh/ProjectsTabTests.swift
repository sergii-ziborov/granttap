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
    }

    override func tearDown() {
        ProjectPreferencesStore.save([:])
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
        XCTAssertEqual(ProjectsCatalog.displayName(old, preference: ProjectPreference(customName: " ")), "nodvox", "blank is no name")
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
        XCTAssertEqual(model.projectDisplayName(id: "p-old"), "nodvox", "an empty name gives the repository's back")
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
}

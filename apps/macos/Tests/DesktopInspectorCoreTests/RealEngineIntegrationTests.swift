import Foundation
import Testing
@testable import DesktopInspectorCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["GRANTTAP_TEST_ENGINE_BINARY"] != nil))
func inspectorReadsAnExistingProjectFromRealEngine() throws {
    let binary = try #require(ProcessInfo.processInfo.environment["GRANTTAP_TEST_ENGINE_BINARY"])
    let fixture = try RealEngineFixture(binaryPath: binary)
    let projectId = "desktop-integration-project"
    let service = InspectorService(client: EngineClient(socketPath: fixture.socketPath))
    let catalog = try service.projectPage()
    #expect(catalog.projects.contains { $0.project_id == projectId })
    #expect(catalog.next_after_project_id == nil)
    #expect(try service.resolveProject(localRoot: fixture.workspacePath) == projectId)
    let snapshot = try service.load(projectId: projectId)
    #expect(!snapshot.version.engine_version.isEmpty)
    #expect(snapshot.project?.project_id == projectId)
    #expect(snapshot.bindings.count == 1)
    #expect(snapshot.bindings.first?.repository_id == "desktop-integration-repo")
    let coverage = try #require(snapshot.coverage)
    #expect(coverage.project_id == projectId)
    #expect(coverage.policy_revision == 1)
    #expect(coverage.required_capabilities == [.shell])
    #expect(coverage.endpoints.count == 1)
    #expect(coverage.endpoints.first?.capabilities.first?.status == .enforced)
    let projectKnowledge = try #require(snapshot.knowledge)
    #expect(projectKnowledge.entries.count == 24)
    #expect(projectKnowledge.incomplete)
    let projectCursor = try #require(projectKnowledge.next_before_version)
    let projectOlder = try service.knowledgePage(projectId: projectId,
        beforeVersion: projectCursor)
    let publicRows = projectKnowledge.entries + projectOlder.entries
    #expect(publicRows.count == 26)
    #expect(publicRows.allSatisfy { $0.visibility == "project" })
    #expect(publicRows.contains { $0.record_id == "public-a" })

    let projectActivity = try #require(snapshot.invocations)
    #expect(projectActivity.events.count == 32)
    #expect(projectActivity.has_older)
    let activityOlder = try service.invocationPage(projectId: projectId,
        beforeSequence: projectActivity.previous_sequence)
    #expect((projectActivity.events + activityOlder.events).count == 35)

    let task = try service.load(projectId: projectId, taskId: "task-a")
    let taskKnowledge = try #require(task.knowledge)
    let taskCursor = try #require(taskKnowledge.next_before_version)
    let taskOlder = try service.knowledgePage(projectId: projectId, taskId: "task-a",
        beforeVersion: taskCursor)
    let taskRows = taskKnowledge.entries + taskOlder.entries
    #expect(taskRows.count == 27)
    #expect(taskRows.contains { $0.record_id == "private-a" })
    #expect(!taskRows.contains { $0.record_id == "private-b" })
    let taskActivity = try #require(task.invocations)
    #expect(taskActivity.events.allSatisfy { $0.event.task_id == "task-a" })

    try fixture.advancePolicy()
    let revised = try service.load(projectId: projectId)
    #expect(revised.policy?.revision == 2)
    #expect(revised.coverage?.policy_revision == 2)
    #expect(revised.coverage?.endpoints.isEmpty == true)
    #expect(revised.coverage?.strict_ready == false)
}

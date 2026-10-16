#if DEBUG
import Foundation

enum ProjectTaskCreationFixture {
    @MainActor static func apply(to model: AppModel, at now: Double) {
        let env = ProcessInfo.processInfo.environment
        guard (env["GRANTTAP_TEST_PROJECT_TASK"] == "1" || env["GRANTTAP_TEST_TAB_FRAMES"] == "1"),
              var mesh = model.meshSnapshots[AppModelDemoMeshFixtures.projectId] else { return }
        mesh.bindings = mesh.bindings?.map { binding in
            var binding = binding
            binding.localPathHint = binding.endpointId == "MacBook" ? "/Users/reviewer/granttap" : "/Users/reviewer/granttap-mcp"
            return binding
        }
        model.meshComputerRoomByEndpointId["MacBook"] = "synthetic-mac"
        model.meshComputerRoomByEndpointId["Workstation"] = "synthetic-workstation"
        if env["GRANTTAP_TEST_TAB_FRAMES"] == "1" {
            let tasks = (0..<240).map { i in
                ProjectMeshTask(taskId: "navigation-task-\(i)", projectId: mesh.projectId, title: "Synthetic task \(i)",
                    goal: "Synthetic navigation sample", state: "working", ownerSessionId: "navigation-chat-\(i)",
                    createdAt: now - 10_000, updatedAt: now - Double(i))
            }
            mesh.tasks += tasks
            mesh.executions += tasks.enumerated().map { i, task in
                .init(taskId: task.taskId, sessionId: "navigation-chat-\(i)", provider: "codex", computerId: "Workstation",
                    workspace: "/Users/reviewer/granttap", activeAt: now - Double(i), startedAt: now - 10_000)
            }
            model.sessions += tasks.enumerated().map { i, task in
                .init(sessionId: "navigation-chat-\(i)", agent: "codex", projectId: mesh.projectId, taskId: task.taskId,
                    title: task.title, cwd: "/Users/reviewer/granttap", state: "working", startedAt: now - 10_000,
                    lastActivityAt: now - Double(i), tokensSession: 20, tokensLastTurn: 5)
            }
        }
        model.meshSnapshots[mesh.projectId] = mesh
    }
}
#endif

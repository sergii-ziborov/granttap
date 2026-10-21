import Foundation
import Combine

/// Refresh the selected Mesh's saved evidence without rebuilding its architecture.
@MainActor
final class ProjectKnowledgeRefresh: ObservableObject {
    enum State { case saved, loading, updated, unavailable }
    @Published private(set) var state = State.saved
    private var generation = UUID()
    let timeout: TimeInterval
    let pollNanoseconds: UInt64

    init(timeout: TimeInterval = 15, pollNanoseconds: UInt64 = 250_000_000) {
        self.timeout = timeout
        self.pollNanoseconds = pollNanoseconds
    }

    func refresh(projectId: String, model: AppModel) async {
        guard !Task.isCancelled, let snapshot = model.meshSnapshots[projectId] else { return }
        let token = UUID()
        generation = token
        let rooms = model.meshProjectSourceRooms[projectId] ?? []
        var available = rooms.contains { model.roomRuntime[$0]?.socketUp == true }
        #if targetEnvironment(macCatalyst)
        available = available || (model.localMCPReader?.isReady == true
                                  && model.localMCPReader?.meshSnapshots[projectId] != nil)
        #endif
        guard available else { state = .unavailable; return }
        state = .loading
        defer { if generation == token && state == .loading { state = .saved } }
        let deadline = Date().addingTimeInterval(timeout)
        await model.refreshProjectInsights(projectId: projectId, requestRemote: true)
        guard generation == token, !Task.isCancelled else { return }
        let tasks = model.meshSnapshots[projectId]?.tasks ?? snapshot.tasks
        for task in tasks {
            model.refreshInvocationHistory(projectId: projectId, taskId: task.taskId)
        }
        let taskKeys = Set(tasks.map { AppModel.invocationTaskKey(projectId, $0.taskId) })
        repeat {
            guard generation == token, !Task.isCancelled else { return }
            let pending = model.invocationPendingRooms.values.contains { roomKey in
                taskKeys.contains { roomKey.hasPrefix("\($0)\u{1f}") }
            }
            let historiesReady = taskKeys.allSatisfy { model.invocationAvailabilityByTask[$0] == "ready" }
            if model.meshSnapshots[projectId]?.generatedAt != snapshot.generatedAt,
               !pending, historiesReady {
                state = .updated
                return
            }
            do { try await Task.sleep(nanoseconds: pollNanoseconds) } catch { return }
        } while Date() < deadline
        state = .unavailable
    }
}

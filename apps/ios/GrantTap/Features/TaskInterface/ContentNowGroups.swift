import SwiftUI

/// What the first screen shows.
///
/// Open executions remain visible until they close. The age window applies only
/// to recently closed or otherwise inactive work.
extension ContentView {
    var currentTaskItems: [TaskListItem] {
        activeTaskItems
    }

    var atRiskTasks: [TaskListItem] {
        currentTaskItems.filter {
            let value = health(for: $0)
            return value != .needsYou && value != .blocked && value < .working
        }
            .sorted {
                health(for: $0) == health(for: $1)
                    ? $0.lastActivityAt > $1.lastActivityAt
                    : health(for: $0) < health(for: $1)
            }
    }

    var activeNowTasks: [TaskListItem] {
        currentTaskItems
            .filter { $0.hasOpenExecution && [.working, .idle].contains(health(for: $0)) }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    var blockedTasks: [TaskListItem] {
        currentTaskItems.filter { health(for: $0) == .blocked }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    var recentTasks: [TaskListItem] {
        Array(TaskListCatalog.items(
            model: model, sessions: taskHistorySessions, history: true
        ).filter {
            !isTaskHidden($0) && !$0.hasOpenExecution && $0.isTerminal
                && TaskRecency.isRecent($0)
        }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }.prefix(3))
    }

}

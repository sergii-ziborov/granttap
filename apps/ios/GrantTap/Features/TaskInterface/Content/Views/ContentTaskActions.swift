import SwiftUI

extension ContentView {
    @ViewBuilder
    func taskActionCard(_ item: TaskListItem) -> some View {
        if let session = item.currentSession {
            TaskSwipeCard(id: item.id, revealed: $revealedSessionAction,
                          open: { open(item) },
                          archive: { archiveTask(item) },
                          send: { handoffSession = session }) {
                TaskListCard(item: item, route: ownerRoute(item))
            }
        } else {
            Button { open(item) } label: {
                TaskListCard(item: item, route: ownerRoute(item))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("task.\(item.id)")
        }
    }

    func archiveTask(_ item: TaskListItem) {
        revealedSessionAction = nil
        item.sessionIds.forEach { model.setSessionArchived($0, true) }
    }
}

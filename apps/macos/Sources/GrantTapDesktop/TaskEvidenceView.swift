import DesktopInspectorCore
import SwiftUI

struct TaskEvidenceView: View {
    @ObservedObject var model: DesktopModel
    @State private var selection: Detail = .conversation

    private enum Detail: String, CaseIterable {
        case conversation = "Conversation"
        case activity = "Tool activity"
        case knowledge = "Knowledge"
    }

    private var taskTitle: String {
        let title = model.meshProject?.tasks.first { $0.task_id == model.taskId }?.title
            ?? model.workspaceSummary?.tasks.first { $0.task_id == model.taskId }?.title
            ?? model.taskId
        return TaskDisplayTitle.plain(title)
    }

    private var taskItem: DesktopTaskItem? {
        DesktopTaskCatalog.items(workspace: model.workspaceSummary, mesh: model.meshProject,
                                 projectName: model.snapshot?.project?.name)
            .first { $0.projectId == model.projectId && $0.taskId == model.taskId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { model.clearTaskSelection() } label: {
                Label("Back to Tasks", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            HStack(alignment: .top, spacing: 12) {
                DesktopAgentBadge(provider: taskItem?.provider, size: 36)
                VStack(alignment: .leading, spacing: 5) {
                    Text(taskTitle)
                        .font(.title2.bold())
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("task.detail.title")
                    Text([taskItem?.projectName, taskItem?.provider?.capitalized]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(DesktopTheme.muted)
                }
                Spacer(minLength: 8)
                if let taskItem {
                    Label(taskItem.stateLabel, systemImage: "circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(taskItem.stateColor)
                }
            }
            Picker("Task detail", selection: $selection) {
                ForEach(Detail.allCases, id: \.self) { detail in
                    Text(detail.rawValue).tag(detail)
                }
            }
            .pickerStyle(.segmented)
            switch selection {
            case .conversation:
                TaskConversationView(activity: model.taskActivity,
                                     loading: model.loadingTaskActivity) {
                    model.refresh()
                }
            case .activity:
                if let snapshot = model.snapshot, snapshot.taskId == model.taskId {
                    activity(snapshot)
                } else {
                    ContentUnavailableView("Tool activity unavailable",
                                           systemImage: "list.bullet.rectangle")
                }
            case .knowledge:
                if let snapshot = model.snapshot, snapshot.taskId == model.taskId {
                    knowledge(snapshot)
                } else {
                    ContentUnavailableView("Knowledge unavailable",
                                           systemImage: "text.book.closed")
                }
            }
        }
    }

    @ViewBuilder private func activity(_ snapshot: InspectorSnapshot) -> some View {
        if let page = snapshot.invocations {
            Text("Provider reports and observed outcomes are labeled separately.")
                .font(.caption).foregroundStyle(.secondary)
            if page.events.isEmpty {
                ContentUnavailableView("No tool activity", systemImage: "list.bullet.rectangle")
            } else {
                List(Array(page.events.reversed())) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.event.tool_name).font(.headline)
                        Text(row.event.phaseLabel)
                        Text("\(row.event.provider) · \(row.event.source) · #\(row.sequence)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            if page.has_older {
                Button("Load older activity") { model.loadOlderInvocations() }
                    .disabled(model.loading)
            }
        } else {
            ContentUnavailableView("Tool activity unavailable", systemImage: "list.bullet.rectangle")
        }
    }

    @ViewBuilder private func knowledge(_ snapshot: InspectorSnapshot) -> some View {
        if let page = snapshot.knowledge {
            Text("Chat-visible and selected Task records")
                .font(.caption).foregroundStyle(.secondary)
            if page.entries.isEmpty {
                ContentUnavailableView("No Knowledge records", systemImage: "text.book.closed")
            } else {
                List(page.entries) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.content).lineLimit(5)
                        Text("\(record.sourceLabel) · \(record.visibility) · Task \(record.task_id)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            if page.incomplete {
                Button("Load older Knowledge") { model.loadOlderKnowledge() }
                    .disabled(model.loading)
            }
        } else {
            ContentUnavailableView("Knowledge unavailable", systemImage: "text.book.closed")
        }
    }
}

import DesktopInspectorCore
import SwiftUI

struct TaskWorkspaceView: View {
    @ObservedObject var model: DesktopModel
    @State private var search = ""
    @State private var scope: Scope = .active

    private enum Scope: String, CaseIterable {
        case active = "Active"
        case all = "All"
        case history = "History"
    }

    private var tasks: [DesktopTaskItem] {
        DesktopTaskCatalog.items(workspace: model.workspaceSummary, mesh: model.meshProject,
                                 projectName: model.snapshot?.project?.name)
            .filter { model.projectId.isEmpty || $0.projectId == model.projectId }
    }

    private var visibleTasks: [DesktopTaskItem] {
        tasks.filter { item in
            (scope == .history ? item.isFinished
             : scope == .all ? true
             : !item.isFinished && (item.hasOpenExecution || item.needsYou
                                    || item.isBlocked || item.state == "handoff"))
                && (search.isEmpty || [item.title, item.projectName, item.provider ?? "", item.stateLabel]
                    .contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        if !model.taskId.isEmpty {
            TaskEvidenceView(model: model)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Tasks").font(.system(size: 30, weight: .bold))
                            .foregroundStyle(DesktopTheme.ink)
                        Text(model.projectId.isEmpty ? "Across Mesh"
                             : model.snapshot?.project?.name ?? "Selected chat")
                            .font(.subheadline).foregroundStyle(DesktopTheme.muted)
                    }
                    Spacer()
                    if !model.projectId.isEmpty {
                        Button("All Tasks") { model.showAllTasks() }
                    }
                }
                HStack(spacing: 12) {
                    TextField("Search Tasks", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("tasks.search")
                    Picker("Task filter", selection: $scope) {
                        ForEach(Scope.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                }
                DesktopSectionHeading(title: scope.rawValue,
                                      count: visibleTasks.count)
                if visibleTasks.isEmpty {
                    ContentUnavailableView(search.isEmpty
                                           ? (scope == .history ? "No finished Tasks"
                                              : scope == .all ? "No Tasks" : "No active Tasks")
                                           : "No matching Tasks",
                                           systemImage: scope == .history ? "clock" : "tray")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(visibleTasks) { item in
                                DesktopTaskCard(item: item) {
                                    model.openWorkspaceTask(projectId: item.projectId,
                                                            taskId: item.taskId)
                                }
                            }
                        }
                        .frame(maxWidth: 1100, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                if let summary = model.workspaceSummary, summary.tasks.count < summary.task_count {
                    Text("Showing \(summary.tasks.count) recent Tasks of \(summary.task_count). Search covers loaded Tasks.")
                        .font(.caption).foregroundStyle(DesktopTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

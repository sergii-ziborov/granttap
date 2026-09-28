import DesktopInspectorCore
import SwiftUI

struct NowDashboardView: View {
    @ObservedObject var model: DesktopModel

    private var tasks: [DesktopTaskItem] {
        DesktopTaskCatalog.items(workspace: model.workspaceSummary, mesh: model.meshProject,
                                 projectName: model.snapshot?.project?.name)
    }
    private var needsYou: [DesktopTaskItem] { tasks.filter(\.needsYou) }
    private var recentlyUpdated: [DesktopTaskItem] { tasks.filter(\.isRecentlyUpdated) }
    private var atRisk: [DesktopTaskItem] { tasks.filter(\.isLastKnownWorking) }
    private var blocked: [DesktopTaskItem] { tasks.filter(\.isBlocked) }
    private var finished: [DesktopTaskItem] { tasks.filter(\.isFinished) }
    private var hasNowActivity: Bool {
        !needsYou.isEmpty || !recentlyUpdated.isEmpty || !atRisk.isEmpty
            || !blocked.isEmpty || !finished.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Now").font(.system(size: 30, weight: .bold))
                            .foregroundStyle(DesktopTheme.ink)
                        Text(workspaceLabel)
                            .font(.subheadline).foregroundStyle(DesktopTheme.muted)
                    }
                    Spacer()
                    Button("All Tasks") { model.showAllTasks() }
                        .buttonStyle(.bordered)
                }

                if tasks.isEmpty {
                    emptyWorkspace
                } else {
                    if !hasNowActivity { quietWorkspace }
                    taskGroup("Needs You", items: needsYou, limit: 5)
                    taskGroup("At Risk", items: atRisk, limit: 4)
                    taskGroup("Working", items: recentlyUpdated, limit: 5)
                    taskGroup("Blocked", items: blocked, limit: 4)
                    taskGroup("Recently Finished", items: finished, limit: 3)
                }
                chatPreview
                connectionFootnote
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 12)
        }
        .accessibilityIdentifier("now.dashboard")
    }

    private var workspaceLabel: String {
        guard let summary = model.workspaceSummary else {
            return model.mcpStatus == nil ? "Connect this Mac to see your work" : "Loading Mesh and Tasks…"
        }
        return "\(summary.task_count) Tasks · \(summary.project_count) chats in Mesh"
    }

    @ViewBuilder private func taskGroup(_ title: String, items: [DesktopTaskItem],
                                        limit: Int) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                DesktopSectionHeading(title: title, count: items.count)
                ForEach(Array(items.prefix(limit))) { item in
                    DesktopTaskCard(item: item) {
                        model.openWorkspaceTask(projectId: item.projectId, taskId: item.taskId)
                    }
                }
                if items.count > limit {
                    Button("See all \(title.lowercased()) Tasks") { model.showAllTasks() }
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var emptyWorkspace: some View {
        DesktopCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "tray")
                    .font(.title2).foregroundStyle(DesktopTheme.muted)
                Text("No Tasks to show yet").font(.headline)
                Text(model.mcpStatus == nil
                     ? "Open Connection to check GrantTap MCP on this Mac."
                     : "Open Mesh to browse your chats and repositories.")
                    .foregroundStyle(DesktopTheme.muted)
                Button(model.mcpStatus == nil ? "Open Connection" : "Open Mesh") {
                    model.selected = model.mcpStatus == nil ? .engine : .project
                }
            }
        }
    }

    private var quietWorkspace: some View {
        DesktopCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.title2).foregroundStyle(DesktopTheme.positive)
                Text("No current activity confirmed").font(.headline)
                Text("Browse Tasks to see earlier work and planned Tasks.")
                    .foregroundStyle(DesktopTheme.muted)
                Button("Browse Tasks") { model.showAllTasks() }
            }
        }
    }

    @ViewBuilder private var chatPreview: some View {
        if !model.projectCatalog.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    DesktopSectionHeading(title: "Chats in Mesh", count: model.projectCatalog.count)
                    Spacer()
                    Button("Browse all") { model.selected = .project }
                        .font(.caption.weight(.semibold))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                          spacing: 12) {
                    ForEach(recentProjects) { project in
                        Button { model.selectProject(project.project_id) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.title3).foregroundStyle(DesktopTheme.positive)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(project.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesktopTheme.ink).lineLimit(2)
                                    Text("\(tasks.filter { $0.projectId == project.project_id }.count) Tasks")
                                        .font(.caption).foregroundStyle(DesktopTheme.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
                            .padding(13)
                            .background(DesktopTheme.raised,
                                        in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(DesktopTheme.line))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var recentProjects: [InspectorProject] {
        let lastActivity = Dictionary(grouping: tasks, by: \.projectId)
            .mapValues { $0.map(\.updatedAt).max() ?? 0 }
        return Array(model.projectCatalog.sorted {
            let left = lastActivity[$0.project_id] ?? $0.created_at
            let right = lastActivity[$1.project_id] ?? $1.created_at
            return left == right ? $0.name < $1.name : left > right
        }.prefix(3))
    }

    private var connectionFootnote: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(model.mcpStatus == nil ? DesktopTheme.caution : DesktopTheme.positive)
                .frame(width: 7, height: 7)
            Text(model.mcpStatus == nil ? "Local MCP unavailable" : "Local MCP connected")
            if let status = model.mcpStatus {
                Text("·")
                Text(status.relayStatus == .online ? "Relay online" : "Relay status unavailable")
            }
            Spacer()
            Button("Connection") { model.selected = .engine }
                .buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(DesktopTheme.muted)
        .padding(.top, 4)
    }
}

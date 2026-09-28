import DesktopInspectorCore
import AppKit
import SwiftUI

struct ProjectDetailView: View {
    @ObservedObject var model: DesktopModel
    @State private var selection: Detail = .overview
    @State private var projectFolderPath = ""
    @State private var search = ""

    private enum Detail: String, CaseIterable {
        case overview = "Overview"
        case graph = "Graph"
        case governance = "Governance"
        case knowledge = "Knowledge"
        case activity = "Tool activity"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mesh").font(.largeTitle.bold())
                    Text("Chats, repositories, people and shared work")
                        .foregroundStyle(.secondary)
                }
                if model.loadingProjects { ProgressView().controlSize(.small) }
                Spacer()
                Button("Reload") { model.loadProjects(reset: true) }
                    .disabled(model.loadingProjects)
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Search chats", text: $search)
                        .textFieldStyle(.roundedBorder)
                    Text("\(model.projectCatalog.count) chats")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(filteredProjects) { item in
                                Button { model.selectProject(item.project_id) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "point.3.connected.trianglepath.dotted")
                                            .foregroundStyle(DesktopTheme.positive)
                                        Text(item.name)
                                            .foregroundStyle(DesktopTheme.ink)
                                            .lineLimit(2)
                                        Spacer(minLength: 0)
                                        if item.project_id == model.projectId {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(item.project_id == model.projectId
                                                ? DesktopTheme.positive.opacity(0.12) : DesktopTheme.surface,
                                                in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .disabled(model.loading)
                            }
                        }
                    }
                    if model.projectCatalogCursor != nil {
                        Button("Load more chats") { model.loadProjects() }
                            .disabled(model.loadingProjects)
                    }
                    DisclosureGroup("Find a local repository folder") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Local repository folder", text: $projectFolderPath)
                                .accessibilityIdentifier("projectFolderPath")
                            HStack {
                                Button("Find") { model.resolveProjectFolderPath(projectFolderPath) }
                                Button("Choose folder…") { chooseProjectFolder() }
                            }
                            .disabled(model.loading)
                        }
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, 8)
                    }
                    .font(.caption)
                    Text(model.message).font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 270)
                .frame(maxHeight: .infinity, alignment: .top)
                Divider()
                ScrollView {
                    projectContents
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var filteredProjects: [InspectorProject] {
        guard !search.isEmpty else { return model.projectCatalog }
        return model.projectCatalog.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Find chat"
        panel.begin { response in
            guard response == .OK, let path = panel.url?.path else { return }
            projectFolderPath = path
            model.resolveProjectFolderPath(path)
        }
    }

    @ViewBuilder private var projectContents: some View {
        if let snapshot = model.snapshot, let project = snapshot.project {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).font(.title2.bold())
                    Text("\(Set(snapshot.bindings.map(\.repository_id)).count) repositories · \(Set(snapshot.bindings.map(\.endpoint_id)).count) computers" +
                         (model.meshProject.map { " · \($0.tasks.count) recent Tasks" } ?? ""))
                        .font(.caption).foregroundStyle(DesktopTheme.muted)
                }
                Picker("Project detail", selection: $selection) {
                    ForEach(Detail.allCases, id: \.self) { detail in
                        Text(detail.rawValue).tag(detail)
                    }
                }
                .pickerStyle(.segmented)
                switch selection {
                case .overview:
                    HStack(spacing: 12) {
                        summaryCard("Repositories", value: "\(Set(snapshot.bindings.map(\.repository_id)).count)", icon: "folder")
                        summaryCard("Governance", value: snapshot.policy.map { "Rev \($0.revision)" }
                                    ?? "Not reported", icon: "checkmark.shield")
                        summaryCard("Graph", value: snapshot.backbone.map { "\($0.nodes.count) nodes" }
                                    ?? "Not reported", icon: "point.3.connected.trianglepath.dotted")
                    }
                    if !snapshot.bindings.isEmpty {
                        Text("Connected repositories").font(.headline)
                        ForEach(snapshot.bindings) { binding in
                            DesktopCard {
                                HStack {
                                    Image(systemName: "folder")
                                    VStack(alignment: .leading) {
                                        Text(binding.local_alias ?? binding.repository_id)
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(binding.endpoint_id) · \(binding.role)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if let mesh = model.meshProject, mesh.project_id == project.project_id {
                    Text("Tasks in this chat").font(.headline)
                        if mesh.tasks.isEmpty {
                            Text("No Tasks in this chat yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(mesh.tasks.sorted { $0.updated_at > $1.updated_at }.prefix(5))) { task in
                                DesktopCard {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(TaskDisplayTitle.plain(task.title)).font(.subheadline.weight(.semibold))
                                                .lineLimit(2)
                                            Text("\(task.state.replacingOccurrences(of: "_", with: " ").capitalized) · \(task.provider?.capitalized ?? "No active provider")")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("Open Task") {
                                            model.openWorkspaceTask(projectId: project.project_id,
                                                                    taskId: task.task_id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text("Knowledge and tool activity show this chat's recorded evidence.")
                        .foregroundStyle(.secondary)
                case .graph:
                    BackboneDetailView(backbone: snapshot.backbone)
                        .frame(minHeight: 480)
                case .governance:
                    GovernanceDetailView(snapshot: snapshot)
                        .frame(minHeight: 480)
                case .knowledge: knowledge(snapshot)
                case .activity: activity(snapshot)
                }
            }
        } else {
            ContentUnavailableView("Choose a chat in Mesh", systemImage: "bubble.left.and.bubble.right")
        }
    }

    private func summaryCard(_ title: String, value: String, icon: String) -> some View {
        DesktopCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline)
            }
        }
    }

    @ViewBuilder private func knowledge(_ snapshot: InspectorSnapshot) -> some View {
        if let page = snapshot.knowledge {
            Text(snapshot.taskId == nil
                 ? "Chat-visible records only"
                 : "Chat-visible and selected Task records")
                .font(.caption)
                .foregroundStyle(.secondary)
            if page.entries.isEmpty {
                ContentUnavailableView("No Knowledge records", systemImage: "text.book.closed")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(page.entries) { record in
                        DesktopCard {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.content).lineLimit(5)
                                Text("\(record.category) · \(record.sourceLabel) · \(record.visibility)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Task \(record.task_id) · version \(record.stream_version)")
                                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
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

    @ViewBuilder private func activity(_ snapshot: InspectorSnapshot) -> some View {
        if let page = snapshot.invocations {
            Text("Invocation evidence records what was reported or observed; it does not confirm an external outcome.")
                .font(.caption).foregroundStyle(.secondary)
            if page.events.isEmpty {
                ContentUnavailableView("No tool activity", systemImage: "list.bullet.rectangle")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(page.events.reversed())) { row in
                        DesktopCard {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.event.tool_name).font(.headline)
                                Text(row.event.phaseLabel)
                                Text("\(row.event.provider) · \(row.event.source) · Task \(row.event.task_id) · #\(row.sequence)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
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
}

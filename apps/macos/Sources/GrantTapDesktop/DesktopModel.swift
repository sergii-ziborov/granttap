import DesktopInspectorCore
import Foundation

@MainActor
final class DesktopModel: ObservableObject {
    enum Section: String, CaseIterable, Hashable {
        case now = "Now"
        case tasks = "Tasks"
        case usage = "Usage"
        case engine = "Connection"
        case project = "Mesh"
        case bindings = "Computers"
        case policy = "Governance"
        case backbone = "Graph"
    }

    @Published var socketPath = EngineClient.configuredSocketPath {
        didSet {
            guard socketPath != oldValue else { return }
            invalidateRead()
            projectCatalog = []
            workspaceSummary = nil
            projectCatalogCursor = nil
            projectCatalogSocketPath = ""
            catalogGeneration = UUID()
            loadingProjects = false
        }
    }
    @Published var projectId = "" { didSet { if projectId != oldValue { invalidateRead() } } }
    @Published var taskId = "" { didSet { if taskId != oldValue { invalidateRead() } } }
    @Published var selected: Section? = .now
    @Published var snapshot: InspectorSnapshot?
    @Published private(set) var meshProject: MeshProjectSnapshot?
    @Published private(set) var taskActivity: TaskActivitySnapshot?
    @Published private(set) var loadingTaskActivity = false
    @Published private(set) var workspaceSummary: MeshWorkspaceSummary?
    @Published var message = "Checking Mesh…"
    @Published var loading = false
    @Published private(set) var mcpStatus: LocalMCPStatus?
    @Published private(set) var mcpMessage = "Checking local MCP…"
    @Published private(set) var projectCatalog: [InspectorProject] = []
    @Published private(set) var projectCatalogCursor: String?
    @Published private(set) var loadingProjects = false
    private var projectCatalogSocketPath = ""
    private var discoveredSocketPath = ""
    private var readGeneration = UUID()
    private var activityGeneration = UUID()
    private var catalogGeneration = UUID()
    private var workspaceGeneration = UUID()

    private func invalidateRead() {
        readGeneration = UUID()
        snapshot = nil
        meshProject = nil
        taskActivity = nil
        loadingTaskActivity = false
        activityGeneration = UUID()
        loading = false
    }

    func checkLocalMCP() {
        Task {
            let priorPath = socketPath
            do {
                let status = try await LocalMCPStatus.fetch()
                mcpStatus = status
                mcpMessage = status.paired
                    ? "GrantTap MCP is installed and paired on this Mac."
                    : "Local MCP detected; no phone is paired."
                if let discovered = status.desktopEngineSocket,
                   socketPath.isEmpty || socketPath == discoveredSocketPath {
                    discoveredSocketPath = discovered
                    socketPath = discovered
                }
                if !socketPath.isEmpty { loadWorkspace() }
            } catch {
                mcpStatus = nil
                mcpMessage = "No local MCP HTTP service detected."
            }
            if !socketPath.isEmpty, !loading, socketPath != priorPath { refresh() }
        }
    }

    func refresh() {
        let path = socketPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            message = "GrantTap MCP has not provided a local Mesh channel."
            snapshot = nil
            return
        }
        loadWorkspace()
        loading = true
        let needsActivity = !project.isEmpty && !task.isEmpty
        loadingTaskActivity = needsActivity
        message = "Reading Mesh…"
        let generation = UUID()
        let activityRead = UUID()
        readGeneration = generation
        activityGeneration = activityRead
        if projectCatalogSocketPath != path && !loadingProjects { loadProjects(reset: true) }
        if needsActivity {
            taskActivity = nil
            loadTaskActivity(path: path, project: project, task: task,
                             generation: activityRead)
        }
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let service = InspectorService(client: EngineClient(socketPath: path))
                    let snapshot = try service.load(projectId: project.isEmpty ? nil : project,
                                                    taskId: task.isEmpty ? nil : task)
                    let mesh = project.isEmpty ? nil : try? service.meshProject(projectId: project)
                    return (snapshot, mesh)
                }.value
                guard readGeneration == generation else { return }
                snapshot = result.0
                meshProject = result.1
                message = "Mesh connected."
            } catch let error as EngineClientError {
                guard readGeneration == generation else { return }
                snapshot = nil
                meshProject = nil
                message = error.description
            } catch {
                guard readGeneration == generation else { return }
                snapshot = nil
                meshProject = nil
                message = "The local Engine read failed."
            }
            loading = false
        }
    }

    private func loadTaskActivity(path: String, project: String, task: String,
                                  generation: UUID) {
        Task {
            for attempt in 0..<3 {
                if attempt > 0 { try? await Task.sleep(for: .seconds(attempt)) }
                guard activityGeneration == generation else { return }
                let activity = try? await Task.detached(priority: .utility) {
                    try InspectorService(client: EngineClient(socketPath: path,
                                                              timeoutSeconds: 16))
                        .taskActivity(projectId: project, taskId: task)
                }.value
                guard activityGeneration == generation else { return }
                if let activity { taskActivity = activity; break }
            }
            loadingTaskActivity = false
        }
    }

    func selectProject(_ id: String) {
        projectId = id
        taskId = ""
        selected = .project
        refresh()
    }

    func selectTask(_ id: String) {
        taskId = id
        selected = .tasks
        refresh()
    }

    func openWorkspaceTask(projectId: String, taskId: String) {
        self.projectId = projectId
        self.taskId = taskId
        selected = .tasks
        refresh()
    }

    func loadWorkspace() {
        let path = socketPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        let generation = UUID()
        workspaceGeneration = generation
        Task {
            do {
                let result = try await Task.detached(priority: .utility) {
                    try InspectorService(client: EngineClient(socketPath: path)).workspaceSummary()
                }.value
                guard workspaceGeneration == generation, socketPath == path else { return }
                workspaceSummary = result
            } catch { /* Status and Engine cards report connection failure. */ }
        }
    }

    func clearTaskSelection() {
        taskId = ""
        projectId = ""
        selected = .tasks
        refresh()
    }

    func showAllTasks() {
        taskId = ""
        projectId = ""
        selected = .tasks
        refresh()
    }

    func loadProjects(reset: Bool = false) {
        let path = socketPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, reset || !loadingProjects else { return }
        if reset {
            projectCatalog = []
            projectCatalogCursor = nil
            projectCatalogSocketPath = ""
        } else if projectCatalogSocketPath != path {
            loadProjects(reset: true)
            return
        }
        let cursor = projectCatalogCursor
        let generation = UUID()
        catalogGeneration = generation
        loadingProjects = true
        Task {
            do {
                let page = try await Task.detached(priority: .userInitiated) {
                    try InspectorService(client: EngineClient(socketPath: path))
                        .projectPage(afterProjectId: cursor)
                }.value
                guard catalogGeneration == generation, socketPath.trimmingCharacters(in: .whitespacesAndNewlines) == path else { return }
                projectCatalog.append(contentsOf: page.projects)
                projectCatalogCursor = page.next_after_project_id
                projectCatalogSocketPath = path
            } catch {
                guard catalogGeneration == generation else { return }
                message = "Mesh chats could not be loaded from this Mac."
            }
            guard catalogGeneration == generation else { return }
            loadingProjects = false
        }
    }

    func resolveProjectFolderPath(_ folderPath: String) {
        let path = socketPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !loading else {
            message = "Enter the local Engine socket path first."
            return
        }
        let enteredRoot = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var isDirectory: ObjCBool = false
        guard enteredRoot.hasPrefix("/"),
              FileManager.default.fileExists(atPath: enteredRoot, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            message = "Choose an existing repository folder."
            return
        }
        let root = URL(fileURLWithPath: enteredRoot).standardizedFileURL.path
        loading = true
        message = "Finding the chat for this repository…"
        Task {
            do {
                let resolved = try await Task.detached(priority: .userInitiated) {
                    try InspectorService(client: EngineClient(socketPath: path))
                        .resolveProject(localRoot: root)
                }.value
                projectId = resolved
                taskId = ""
                loading = false
                refresh()
            } catch {
                message = "No Mesh chat is linked to that repository folder."
                loading = false
            }
        }
    }

}

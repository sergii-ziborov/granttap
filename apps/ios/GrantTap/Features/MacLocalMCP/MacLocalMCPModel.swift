#if targetEnvironment(macCatalyst)
import Foundation

@MainActor
final class MacLocalMCPModel: ObservableObject {
    @Published private(set) var status: MacLocalMCPStatus?
    @Published private(set) var workspace: MacLocalWorkspace?
    @Published private(set) var catalogProjects: [MacLocalWorkspace.Mesh]?
    @Published private(set) var meshSnapshots: [String: ProjectMeshSnapshot] = [:]
    @Published private(set) var message: String?
    @Published private(set) var refreshing = false
    @Published private(set) var hasCheckedLocalMCP = false
    private var firstLocalCheckAt: Date?
    private var nextAccountAccessAttempt = Date.distantPast
    @Published private(set) var machineLoad: MacLocalMachineLoad?
    @Published private(set) var machineLoadError: String?
    @Published private(set) var usageError: String?
    @Published private(set) var sessionUsage: [String: SessionUsageSnapshot] = [:]
    @Published private(set) var liveCatalog: MacLocalLiveCatalog?
    private var usageRefreshInFlight = false
    private var lastUsageReadAt: Date?
    @Published var pendingAutoAcceptProjects: Set<String> = []
    @Published var pausedAutoAcceptProjects: Set<String> = []
    private var imageRoutes: [String: (projectId: String, taskId: String, cursor: String?)] = [:]

    var isReady: Bool { status?.desktopEngineSocket != nil && workspace != nil }

    func refreshMachineLoad() async {
        guard let socket = status?.desktopEngineSocket else {
            machineLoadError = L("Local MCP is unavailable.")
            return
        }
        do {
            let data = try await MacLocalMCPClient.read(socketPath: socket,
                operation: "desktop.machine_load", input: nil)
            let value = try JSONDecoder().decode(MacLocalMachineLoad.self, from: data)
            guard value.isValid else { throw MacLocalMCPError.incompatible }
            machineLoad = value
            machineLoadError = nil
        } catch {
            machineLoadError = L("Could not read process load from this Mac.")
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        if firstLocalCheckAt == nil { firstLocalCheckAt = Date() }
        refreshing = true
        defer { refreshing = false }
        liveCatalog = nil
        do {
            let discovered = try await MacLocalMCPClient.status()
            status = discovered
            hasCheckedLocalMCP = true
            guard let socket = discovered.desktopEngineSocket else {
                workspace = nil
                message = L("Local MCP is running, but its Mesh reader is unavailable.")
                return
            }
            if MacNativeAccess.shared.token == nil { _ = await restoreAccountAccess(discovered) }
            async let liveRead = try? MacLocalMCPClient.liveCatalog(socketPath: socket)
            let snapshot: MacLocalWorkspace
            do { snapshot = try await MacLocalMCPClient.workspace(socketPath: socket) }
            catch {
                guard await restoreAccountAccess(discovered) else { throw error }
                snapshot = try await MacLocalMCPClient.workspace(socketPath: socket)
            }
            workspace = snapshot
            catalogProjects = snapshot.projects == nil
                ? try? await MacLocalMCPClient.catalog(socketPath: socket, workspace: snapshot) : nil
            let projects = snapshot.projects ?? catalogProjects ?? []
            let fetched = try await MacLocalMCPClient.meshSnapshots(socketPath: socket)
            liveCatalog = await liveRead
            Task { await refreshUsage(socketPath: socket) }
            if !fetched.isEmpty { meshSnapshots = fetched }
            message = fetched.count == projects.count ? nil :
                L("This MCP version cannot yet provide the complete Mesh view.")
        } catch {
            if status == nil {
                message = nil
                let timedOut = (error as? URLError)?.code == .timedOut
                hasCheckedLocalMCP = !timedOut ||
                    Date().timeIntervalSince(firstLocalCheckAt ?? Date()) >= 30
            } else {
                message = L("The local MCP stopped responding. The last list may be stale.")
                hasCheckedLocalMCP = true
            }
        }
    }

    private func restoreAccountAccess(_ status: MacLocalMCPStatus) async -> Bool {
        guard status.accountLinkSaved == true, let account = GrantTapAccountAPI.session,
              Date() >= nextAccountAccessAttempt else { return false }
        nextAccountAccessAttempt = Date().addingTimeInterval(30)
        do {
            try await MacNativeAccess.shared.authorizeWithAccount(account.token)
            return true
        } catch { return false }
    }

    func refreshUsage(socketPath: String) async {
        guard !usageRefreshInFlight,
              lastUsageReadAt.map({ Date().timeIntervalSince($0) > (usageError == nil ? 120 : 15) })
                ?? true else { return }
        usageRefreshInFlight = true
        defer {
            usageRefreshInFlight = false
            lastUsageReadAt = Date()
        }
        do {
            let usage = try await MacLocalMCPClient.usage(socketPath: socketPath)
            CapabilityUsageStore.shared.merge(usage.status.events, sourceNamespace: "local-mac")
            CapabilityTotalsStore.shared.apply(usage.status.totals, fromRoom: "local-mac")
            sessionUsage = Dictionary(usage.sessions.map { ($0.key, $0) },
                                      uniquingKeysWith: { first, _ in first })
            usageError = nil
        } catch {
            usageError = L("Local tool usage is unavailable from this MCP.")
        }
    }

    func activity(for task: MacLocalWorkspace.Task) async throws -> MacLocalTaskActivity {
        guard let socket = status?.desktopEngineSocket else { throw MacLocalMCPError.unavailable }
        let activity = try await MacLocalMCPClient.activity(socketPath: socket, task: task)
        registerImages(activity)
        return activity
    }

    func enrichedMesh(projectId: String, refreshGraph: Bool = false) async throws -> ProjectMeshSnapshot {
        guard let socket = status?.desktopEngineSocket else { throw MacLocalMCPError.unavailable }
        let snapshot = try await MacLocalMCPClient.meshSnapshot(
            socketPath: socket, projectId: projectId, enrich: true, refreshGraph: refreshGraph
        )
        meshSnapshots[projectId] = snapshot
        return snapshot
    }

    func activity(for session: SessionInfo, cursor: String? = nil) async throws -> MacLocalTaskActivity {
        guard let socket = status?.desktopEngineSocket,
              let projectId = session.projectId, let taskId = session.taskId else {
            throw MacLocalMCPError.unavailable
        }
        let activity = try await MacLocalMCPClient.activity(
            socketPath: socket, projectId: projectId, taskId: taskId, cursor: cursor
        )
        registerImages(activity)
        return activity
    }

    private func registerImages(_ activity: MacLocalTaskActivity) {
        if imageRoutes.count > 1_024 { imageRoutes.removeAll() }
        for entry in activity.entries {
            let route = (activity.project_id, activity.task_id, activity.history?.requestedCursor)
            if entry.attachments?.contains("Image") == true { imageRoutes[entry.id] = route }
            for image in entry.images ?? [] { imageRoutes[image.id] = route }
        }
    }

    func image(forEntryId id: String) async throws -> Data {
        guard let socket = status?.desktopEngineSocket, let route = imageRoutes[id] else {
            throw MacLocalMCPError.unavailable
        }
        return try await MacLocalMCPClient.image(socketPath: socket, projectId: route.projectId,
                                                  taskId: route.taskId, imageId: id, historyCursor: route.cursor)
    }
}
#endif

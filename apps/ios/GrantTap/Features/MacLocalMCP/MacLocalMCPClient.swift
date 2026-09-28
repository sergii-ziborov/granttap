#if targetEnvironment(macCatalyst)
import Darwin
import Foundation

struct MacLocalMCPStatus: Decodable, Sendable {
    let schema: String
    let ok: Bool
    let service: String
    let computer: String
    let endpointId: String?
    let version: String
    let paired: Bool
    let relayStatus: String?
    let phoneReachability: String?
    let desktopEngineSocket: String?
    var providers: [MacProviderReadiness]? = nil
}

struct MacLocalWorkspace: Decodable, Sendable {
    struct Mesh: Decodable, Identifiable, Sendable {
        let project_id: String
        let name: String
        let task_count: Int
        let repository_count: Int
        var id: String { project_id }
    }

    struct Task: Decodable, Identifiable, Sendable {
        let project_id: String
        let project_name: String
        let task_id: String
        let title: String
        let state: String
        let updated_at: Double
        let provider: String?
        let has_open_execution: Bool?
        let last_execution_active_at: Double?
        var id: String { "\(project_id):\(task_id)" }

        var isRecentlyWorking: Bool {
            guard state == "working", has_open_execution == true,
                  let last_execution_active_at, last_execution_active_at > 0 else { return false }
            let seconds = last_execution_active_at > 10_000_000_000
                ? last_execution_active_at / 1_000 : last_execution_active_at
            return abs(Date().timeIntervalSince1970 - seconds) < 15 * 60
        }

        var isOpenWithoutRecentActivity: Bool {
            state == "working" && has_open_execution == true && !isRecentlyWorking
        }

        var stateLabel: String {
            if isRecentlyWorking { return L("Working") }
            if isOpenWithoutRecentActivity { return L("Open") }
            if state == "working" { return L("Idle") }
            return state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    let operation: String
    let project_count: Int
    let task_count: Int
    let projects: [Mesh]?
    let tasks: [Task]
}

struct MacLocalTaskActivity: Decodable, Sendable {
    struct Entry: Decodable, Identifiable, Sendable {
        let id: String
        let kind: String
        let text: String
        let created_at: Double
        let tool_name: String?
        let capabilities: [ObservedCapability]?
        let duration_ms: Int?
        let estimated_context_tokens: Int?
        let mcp_server: String?
        let skill: String?
        let summary: String?
        let attachments: [String]?
        let images: [MessageImageAttachment]?
        let call_text: String?
        let result_text: String?
        let detail_truncated: Bool?
        let file_changes: [RecordedFileChange]?
        let file_changes_complete: Bool?
        let lines_added: Int?
        let lines_removed: Int?
        let diff_preview: String?
        let outcome: CapabilityOutcome?
    }

    let operation: String
    let project_id: String
    let task_id: String
    let session_id: String?
    let agent: String?
    let state: String?
    let entries: [Entry]
    let truncated: Bool
    let history: TranscriptHistoryPage?
}

private struct MacLocalProjectCatalog: Decodable {
    struct Page: Decodable {
        struct Row: Decodable {
            let project_id: String
            let name: String
        }
        let projects: [Row]
        let next_after_project_id: String?
    }
    let operation: String
    let page: Page
}

enum MacLocalMCPError: Error {
    case unavailable, untrusted, incompatible
}

enum MacLocalMCPClient {
    static func status() async throws -> MacLocalMCPStatus {
        let rawPort = ProcessInfo.processInfo.environment["GRANTTAP_MCP_HTTP_PORT"] ?? "17342"
        guard let port = Int(rawPort), (1...65_535).contains(port),
              let url = URL(string: "http://127.0.0.1:\(port)/desktop/status") else {
            throw MacLocalMCPError.unavailable
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 65_536,
              let status = try? JSONDecoder().decode(MacLocalMCPStatus.self, from: data),
              status.schema == "granttap.desktop-status.v1", status.ok,
              status.service == "granttap-mcp", status.computer.utf8.count <= 160,
              status.version.utf8.count <= 64 else {
            throw MacLocalMCPError.incompatible
        }
        return status
    }

    static func workspace(socketPath: String) async throws -> MacLocalWorkspace {
        let data = try await read(socketPath: socketPath, operation: "desktop.workspace", input: nil)
        let workspace = try JSONDecoder().decode(MacLocalWorkspace.self, from: data)
        guard workspace.operation == "desktop.workspace", workspace.project_count >= 0,
              workspace.task_count >= 0, workspace.tasks.count <= 256,
              workspace.tasks.count <= workspace.task_count,
              (workspace.projects?.count ?? 0) <= 256,
              (workspace.projects?.count ?? 0) <= workspace.project_count,
              workspace.projects?.allSatisfy({
                  !$0.project_id.isEmpty && $0.name.utf16.count <= 160
                      && $0.task_count >= 0 && $0.repository_count >= 0
              }) ?? true,
              workspace.tasks.allSatisfy({
                  !$0.project_id.isEmpty && !$0.task_id.isEmpty && !$0.title.isEmpty
                      && $0.title.utf16.count <= 160 && $0.project_name.utf16.count <= 160
              }) else { throw MacLocalMCPError.incompatible }
        return workspace
    }

    static func activity(socketPath: String, task: MacLocalWorkspace.Task) async throws
        -> MacLocalTaskActivity {
        try await activity(socketPath: socketPath, projectId: task.project_id, taskId: task.task_id)
    }

    static func activity(socketPath: String, projectId: String, taskId: String,
                         cursor: String? = nil) async throws
        -> MacLocalTaskActivity {
        var input = ["project_id": projectId, "task_id": taskId]
        if let cursor { input["history_cursor"] = cursor }
        let data = try await read(socketPath: socketPath, operation: "desktop.task_activity", input: input)
        let activity = try JSONDecoder().decode(MacLocalTaskActivity.self, from: data)
        guard activity.operation == "desktop.task_activity",
              activity.project_id == projectId, activity.task_id == taskId,
              activity.entries.count <= 256,
              activity.entries.allSatisfy({ $0.text.utf16.count <= 16_384
                  && ($0.images?.count ?? 0) <= 32
                  && ($0.images?.allSatisfy(\.isValid) ?? true) }) else {
            throw MacLocalMCPError.incompatible
        }
        return activity
    }

    static func meshSnapshot(socketPath: String, projectId: String,
                             enrich: Bool = false) async throws
        -> ProjectMeshSnapshot {
        let data = try await read(socketPath: socketPath, operation: "desktop.mesh_snapshot",
                                  input: ["project_id": projectId,
                                          "enrich": enrich ? "true" : "false"])
        let snapshot = try JSONDecoder().decode(ProjectMeshSnapshot.self, from: data)
        guard snapshot.type == "mesh.snapshot", snapshot.projectId == projectId,
              snapshot.project.projectId == projectId, snapshot.sessionId == projectId,
              snapshot.tasks.count <= 64, (snapshot.bindings?.count ?? 0) <= 64,
              snapshot.executions.count <= 128 else { throw MacLocalMCPError.incompatible }
        return snapshot
    }

    static func catalog(socketPath: String, workspace: MacLocalWorkspace) async throws
        -> [MacLocalWorkspace.Mesh] {
        var rows: [MacLocalWorkspace.Mesh] = []
        var after: String?
        let counts = Dictionary(grouping: workspace.tasks, by: \.project_id)
        repeat {
            let cursor = after
            let data = try await catalogPage(socketPath: socketPath, cursor: cursor)
            let page = try JSONDecoder().decode(MacLocalProjectCatalog.self, from: data)
            guard page.operation == "project.listed", page.page.projects.count <= 50,
                  rows.count + page.page.projects.count <= 256,
                  page.page.projects.allSatisfy({ !$0.project_id.isEmpty && $0.name.utf16.count <= 160 }),
                  page.page.next_after_project_id == nil
                    || page.page.next_after_project_id != after else {
                throw MacLocalMCPError.incompatible
            }
            rows += page.page.projects.map {
                MacLocalWorkspace.Mesh(project_id: $0.project_id, name: $0.name,
                                       task_count: counts[$0.project_id]?.count ?? 0,
                                       repository_count: 0)
            }
            after = page.page.next_after_project_id
        } while after != nil
        return rows
    }

    static func read(socketPath: String, operation: String, input: [String: String]?) async throws
        -> Data {
        #if DEBUG
        return try await Task.detached(priority: .userInitiated) {
            try MacLocalMCPBridge(socketPath: socketPath).read(operation: operation, input: input)
        }.value
        #else
        return try await MacNativeTransport.invoke(operation: operation, input: input)
        #endif
    }
    private static func catalogPage(socketPath: String, cursor: String?) async throws -> Data {
        #if DEBUG
        return try await Task.detached(priority: .userInitiated) {
            try MacLocalMCPBridge(socketPath: socketPath).read(operation: "project.list", input: nil, catalogAfter: cursor)
        }.value
        #else
        var input: [String: Any] = ["limit": 50]
        if let cursor { input["after_project_id"] = cursor }
        return try await MacNativeTransport.invoke(operation: "project.list", input: input)
        #endif
    }
}

#endif

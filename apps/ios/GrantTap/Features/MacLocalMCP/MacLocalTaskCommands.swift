#if targetEnvironment(macCatalyst)
import Foundation

struct MacTaskPreferences: Decodable {
    let operation: String
    let accepted: Bool
    let session_id: String?
    let generated_at: Double?
    let error: String?
    let paused: Bool?
    let access_level: String?
    let excluded: Bool?
    let level: String?
    let shell_allowed: Bool?
    let mcp_disabled: [String]?
    let skills_disabled: [String]?

    func applying(to source: SessionInfo) -> SessionInfo {
        guard accepted, session_id == source.sessionId else { return source }
        var session = source
        session.paused = paused
        if let access_level { session.accessLevel = access_level }
        session.shellAllowed = shell_allowed
        if let disabled = mcp_disabled {
            session.mcpServers = session.mcpServers?.map { row in
                var row = row
                if disabled.contains(row.name) { row.allowed = false }
                return row
            }
        }
        if let disabled = skills_disabled {
            session.skills = session.skills?.map { row in
                var row = row
                if disabled.contains(row.name) { row.allowed = false }
                return row
            }
        }
        return session
    }
}

/// Commands use the same authenticated desktop channel as Task messages.
@MainActor
enum MacLocalTaskCommands {
    typealias Invoke = (String, [String: Any]) async throws -> Data

    static func scope(_ session: SessionInfo) throws -> [String: Any] {
        guard let project = session.projectId, !project.isEmpty,
              let task = session.taskId, !task.isEmpty, !session.sessionId.isEmpty else {
            throw MacLocalMCPError.incompatible
        }
        return ["project_id": project, "task_id": task, "session_id": session.sessionId]
    }

    static func control(_ session: SessionInfo, action: String, continue shouldContinue: Bool = false,
                        invoke: Invoke = { try await MacNativeTransport.invoke(operation: $0, input: $1) }) async throws -> Data {
        guard ["pause", "resume", "compact"].contains(action) else { throw MacLocalMCPError.incompatible }
        var input = try scope(session)
        input["action"] = action
        if action == "resume" { input["continue"] = shouldContinue }
        let data = try await invoke("desktop.task_control", input)
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              envelope["operation"] as? String == "desktop.task_control", let result = envelope["result"],
              let row = result as? [String: Any], row["sessionId"] as? String == session.sessionId,
              row["type"] as? String == (action == "compact" ? "session.compact.result" : "session.control.result"),
              action == "compact" || row["action"] as? String == action,
              row["ok"] is Bool, let message = row["message"] as? String, message.count <= 1_000 else {
            throw MacLocalMCPError.incompatible
        }
        return try JSONSerialization.data(withJSONObject: result)
    }

    static func preferences(_ session: SessionInfo, changes: [String: Any] = [:],
                            invoke: Invoke = { try await MacNativeTransport.invoke(operation: $0, input: $1) }) async throws -> MacTaskPreferences {
        var input = changes
        input.merge(try scope(session)) { _, scoped in scoped }
        let data = try await invoke("desktop.task_preferences", input)
        let result = try JSONDecoder().decode(MacTaskPreferences.self, from: data)
        guard result.operation == "desktop.task_preferences", (result.error?.count ?? 0) <= 500 else {
            throw MacLocalMCPError.incompatible
        }
        if result.accepted {
            guard result.session_id == session.sessionId, result.paused != nil, result.excluded != nil,
                  let level = result.level, AppModel.autoAcceptLevels.contains(level),
                  result.access_level == nil || ["read-only", "workspace", "full"].contains(result.access_level!),
                  (result.mcp_disabled?.count ?? 0) <= 256, (result.skills_disabled?.count ?? 0) <= 256 else {
                throw MacLocalMCPError.incompatible
            }
        }
        return result
    }

    static func capabilities(_ session: SessionInfo,
                             invoke: Invoke = { try await MacNativeTransport.invoke(operation: $0, input: $1) }) async throws -> MacTaskCapabilities {
        let data = try await invoke("desktop.task_capabilities", scope(session))
        let result = try JSONDecoder().decode(MacTaskCapabilities.self, from: data)
        guard result.operation == "desktop.task_capabilities", result.project_id == session.projectId,
              result.task_id == session.taskId, result.session_id == session.sessionId,
              result.mcp_servers.count <= 64, result.skills.count <= 64 else { throw MacLocalMCPError.incompatible }
        return result
    }
}
#endif

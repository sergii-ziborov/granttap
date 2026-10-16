#if targetEnvironment(macCatalyst)
import Foundation

struct MacTaskCapabilities: Decodable {
    let operation: String
    let project_id: String
    let task_id: String
    let session_id: String
    let mcp_servers: [McpServerInfo]
    let skills: [SkillInfo]
    let shell_allowed: Bool

    func applying(to source: SessionInfo) -> SessionInfo {
        guard project_id == source.projectId, task_id == source.taskId, session_id == source.sessionId else { return source }
        var session = source
        session.mcpServers = mcp_servers
        session.skills = skills
        session.shellAllowed = shell_allowed
        return session
    }
}

@MainActor
extension AppModel {
    func refreshLocalTaskCapabilities(_ sessionId: String) async {
        guard !demoMode, localTaskControlsAvailable(sessionId),
              let session = knownSession(for: sessionId, preferredAgent: nil) else { return }
        do {
            let result = try await MacLocalTaskCommands.capabilities(session)
            localMCPReader?.taskCapabilities[sessionId] = result
            mutateSession(sessionId) { current in
                let enriched = result.applying(to: current)
                current = localMCPReader?.taskPreferences[sessionId]?.applying(to: enriched) ?? enriched
            }
        } catch { append("Local Task capability catalog could not refresh") }
    }
}
#endif

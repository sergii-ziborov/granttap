#if targetEnvironment(macCatalyst)
import Foundation

struct MacLocalSkill: Decodable, Identifiable {
    let name: String
    let description: String?
    var id: String { name }
}

private struct MacLocalSkillsEnvelope: Decodable {
    let operation: String
    let project_id: String
    let endpoint_id: String
    let skills: [MacLocalSkill]
}

extension MacLocalMCPModel {
    func installedSkills(projectId: String) async throws -> [MacLocalSkill] {
        guard let socket = status?.desktopEngineSocket,
              let endpointId = status?.endpointId else {
            throw MacLocalMCPError.unavailable
        }
        let data = try await MacLocalMCPClient.read(
            socketPath: socket, operation: "desktop.installed_skills",
            input: ["project_id": projectId]
        )
        let envelope = try JSONDecoder().decode(MacLocalSkillsEnvelope.self, from: data)
        guard envelope.operation == "desktop.installed_skills",
              envelope.project_id == projectId, envelope.endpoint_id == endpointId,
              envelope.skills.count <= 64,
              envelope.skills.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 128
                  && ($0.description?.count ?? 0) <= 500 }) else {
            throw MacLocalMCPError.incompatible
        }
        return envelope.skills
    }
}
#endif

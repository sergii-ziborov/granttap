#if targetEnvironment(macCatalyst)
import Foundation
import SwiftUI

struct MacLocalProjectApproval: Decodable {
    let operation: String
    let project_id: String
    let endpoint_id: String
    let level: String
    let paused: Bool
}

extension MacLocalMCPModel {
    func projectApproval(projectId: String, level: String? = nil) async throws
        -> MacLocalProjectApproval {
        guard let socket = status?.desktopEngineSocket, let endpoint = status?.endpointId else {
            throw MacLocalMCPError.unavailable
        }
        var input = ["project_id": projectId]
        if let level { input["level"] = level }
        let data = try await MacLocalMCPClient.read(socketPath: socket,
            operation: "desktop.project_auto_accept", input: input)
        let result = try JSONDecoder().decode(MacLocalProjectApproval.self, from: data)
        guard result.operation == "desktop.project_auto_accept", result.project_id == projectId,
              result.endpoint_id == endpoint, AppModel.autoAcceptLevels.contains(result.level) else {
            throw MacLocalMCPError.incompatible
        }
        return result
    }
}

extension AppModel {
    func refreshLocalProjectApproval(projectId: String, level: String? = nil) async {
        guard let reader = localMCPReader, reader.isReady else { return }
        do {
            let result = try await reader.projectApproval(projectId: projectId, level: level)
            autoAcceptByProjectByRoom["local-mac", default: [:]][projectId] = result.level
            if result.paused { reader.pausedAutoAcceptProjects.insert(projectId) }
            else { reader.pausedAutoAcceptProjects.remove(projectId) }
            if level != nil { projectPolicyErrors.removeValue(forKey: projectId) }
        } catch {
            projectPolicyErrors[projectId] = L("Could not read or update auto-accept on this Mac. Retry.")
        }
    }

    func setLocalProjectAutoAccept(projectId: String, level: String) -> Bool {
        guard let reader = localMCPReader, reader.isReady,
              reader.meshSnapshots[projectId] != nil else { return false }
        guard !reader.pendingAutoAcceptProjects.contains(projectId) else { return false }
        desiredAutoAcceptByProject[projectId] = level
        reader.pendingAutoAcceptProjects.insert(projectId)
        Task {
            await refreshLocalProjectApproval(projectId: projectId, level: level)
            reader.pendingAutoAcceptProjects.remove(projectId)
        }
        return true
    }
}

struct MacLocalProjectApprovalRow: View {
    let projectId: String
    @ObservedObject var reader: MacLocalMCPModel
    @ObservedObject var model: AppModel

    var body: some View {
        let actual = model.projectAutoAcceptLevel(projectId: projectId, roomId: "local-mac")
        let pending = reader.pendingAutoAcceptProjects.contains(projectId)
        HStack {
            Label(reader.status?.computer ?? L("This Mac"), systemImage: "desktopcomputer")
            Spacer()
            Text(pending ? L("Applying…") : actual == nil ? L("Reading…") : L("Applied"))
                .font(.caption).foregroundStyle(!pending && actual != nil ? Theme.ok : Theme.muted)
        }
        if reader.pausedAutoAcceptProjects.contains(projectId) {
            Text(L("Auto-accept is paused on this computer.")).font(.caption).foregroundStyle(Theme.riskMed)
        }
        if let error = model.projectPolicyErrors[projectId] {
            Text(error).font(.caption).foregroundStyle(Theme.riskHigh)
            Button(L("Retry")) { Task { await model.refreshLocalProjectApproval(projectId: projectId) } }
        }
    }
}
#endif

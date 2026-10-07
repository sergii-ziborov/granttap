import SwiftUI

extension TaskHandoffSheet {
    func applyDefaults() {
        let defaults = defaultSelection
        if targetRoom.isEmpty { targetRoom = defaults.room }
        if targetProvider.isEmpty { targetProvider = defaults.provider }
    }

    func submitHandoff() {
        #if targetEnvironment(macCatalyst)
        if model.usesLocalMCP(for: session) {
            submitLocalHandoff()
            return
        }
        #endif
        if performHandoff(targetRoom: targetRoom, targetProvider: targetProvider) { dismiss() }
    }

    /// Another computer when there is one, else this one with another agent.
    var defaultSelection: (room: String, provider: String) {
        let source = AgentIdentity.normalize(session.agent)
        let otherComputer = targets.first {
            $0.id != sourceRoom && (localComputerId == nil || computerName($0) != localComputerId)
        }
        if let otherComputer { return (otherComputer.id, source) }
        let enabled = AgentIdentity.composeIds.filter {
            $0 != source && model.agentMeshPreferences.isProviderEnabled($0)
        }
        let preferred = source == "claude" ? "codex" : "claude"
        let provider = enabled.contains(preferred) ? preferred : enabled.first ?? ""
        let room = targets.first?.id ?? (localComputerId == nil ? "" : "local-mcp")
        return (room, provider)
    }

    @discardableResult
    func performHandoff(targetRoom: String, targetProvider: String) -> Bool {
        let comment = userComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TaskHandoffReadiness.isReady(
                  readinessChecks(room: targetRoom, provider: targetProvider)
              ),
              let computer = destinationComputer(for: targetRoom) else { return false }
        let normalizedProvider = AgentIdentity.normalize(targetProvider)
        guard AgentIdentity.composeIds.contains(normalizedProvider),
              model.agentMeshPreferences.isProviderEnabled(normalizedProvider),
              !sameAgentHere, comment.count <= 1_000,
              targetModel.isEmpty || modelOptions.contains(where: { $0.id == targetModel }) else {
            return false
        }
        model.prepareTaskHandoff(
            session: session, targetProvider: normalizedProvider,
            targetComputer: computer, targetModel: targetModel.isEmpty ? nil : targetModel,
            userComment: comment.isEmpty ? nil : comment,
            checkpoint: checkpointUncommitted && hasUncommittedWork,
            push: pushBranch && targetRoom != sourceRoom
        )
        return true
    }

    func destinationComputer(for room: String) -> String? {
        if room == "local-mcp" { return localComputerId }
        return targets.first(where: { $0.id == room }).map(computerName)
    }

    func computerName(_ connection: LinkedComputer) -> String {
        let published = connection.lastMachineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return published.isEmpty ? connection.displayName : published
    }

    #if targetEnvironment(macCatalyst)
    func submitLocalHandoff() {
        guard isReady, !sameAgentHere, userComment.count <= 1_000,
              let computer = destinationComputer(for: targetRoom),
              let reader = model.localMCPReader else { return }
        submitting = true
        handoffError = nil
        Task {
            do {
                let result = try await reader.handoff(
                    session, provider: AgentIdentity.normalize(targetProvider), computer: computer,
                    targetModel: targetModel.isEmpty ? nil : targetModel,
                    comment: userComment.trimmingCharacters(in: .whitespacesAndNewlines),
                    checkpoint: checkpointUncommitted && hasUncommittedWork,
                    push: pushBranch && targetRoom != sourceRoom
                )
                if result.accepted { dismiss() }
                else { handoffError = result.error ?? L("The handoff was not accepted.") }
            } catch {
                handoffError = L("The local handoff service is unavailable. Check GrantTap MCP.")
            }
            submitting = false
        }
    }
    #endif
}

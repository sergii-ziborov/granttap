import SwiftUI

extension TaskHandoffSheet {
    func applyDefaults() {
        observesHandoff = true
        let defaults = defaultSelection
        if targetRoom.isEmpty { targetRoom = defaults.room }
        if targetProvider.isEmpty { targetProvider = defaults.provider }
    }

    func submitHandoff() {
        if cloudRun != nil { dismiss(); return }
        #if targetEnvironment(macCatalyst)
        if model.usesLocalTaskDelivery(for: session) {
            submitLocalHandoff()
            return
        }
        #endif
        guard !submitting, isReady, let computer = destinationComputer(for: targetRoom) else { return }
        submitting = true
        handoffError = nil
        let previous = previousHandoffEvents
        handoffNotBefore = session.projectId.flatMap { model.meshSnapshots[$0]?.generatedAt } ?? 0
        Task {
            do {
                try await model.ensureProjectComputerNetwork(for: session, targetComputer: computer)
                guard observesHandoff else { return }
                if performHandoff(targetRoom: targetRoom, targetProvider: targetProvider, completion: { error in
                    if error != nil { handoffError = L("The handoff was not accepted.") }
                }) {
                    await waitForHandoff(previousEvents: previous, computer: computer)
                } else { handoffError = L("The handoff was not accepted.") }
            } catch {
                handoffError = L("The computers have not confirmed this Project's transfer access. Check their connections and retry.")
            }
            submitting = false
        }
    }

    /// Another computer when there is one, else this one with another agent.
    var defaultSelection: (room: String, provider: String) {
        let source = AgentIdentity.normalize(session.agent)
        let otherComputer = targets.first {
            $0.id != sourceRoom && (localComputerId == nil || destinationComputer(for: $0.id) != localComputerId)
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

    /// What the cloud runner is asked for: a Codex Cloud environment, Claude's effort.
    var cloudLaunch: ProjectMeshCloudLaunch? {
        guard let cloud = cloudTarget else { return nil }
        let environment = cloudEnvironment.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProjectMeshCloudLaunch(
            environment: cloud.provider == "codex" && !environment.isEmpty ? String(environment.prefix(160)) : nil,
            effort: cloud.provider == "claude" && !targetEffort.isEmpty ? targetEffort : nil
        )
    }

    @discardableResult
    func performHandoff(targetRoom: String, targetProvider: String,
                        completion: ((Error?) -> Void)? = nil) -> Bool {
        let comment = userComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let cloud = TaskHandoffCloudTarget(tag: targetRoom)
        let provider = cloud?.provider ?? targetProvider
        guard TaskHandoffReadiness.isReady(
                  readinessChecks(room: targetRoom, provider: provider)
              ),
              let computer = destinationComputer(for: targetRoom) else { return false }
        let normalizedProvider = AgentIdentity.normalize(provider)
        guard AgentIdentity.composeIds.contains(normalizedProvider),
              model.agentMeshPreferences.isProviderEnabled(normalizedProvider),
              !sameAgentHere, comment.count <= 1_000,
              targetModel.isEmpty || modelOptions.contains(where: { $0.id == targetModel }) else {
            return false
        }
        return model.prepareTaskHandoff(
            session: session, targetProvider: normalizedProvider,
            targetComputer: computer, targetModel: targetModel.isEmpty ? nil : targetModel,
            userComment: comment.isEmpty ? nil : comment,
            checkpoint: checkpointUncommitted,
            push: pushBranch && targetRoom != sourceRoom, cloud: cloudLaunch, completion: completion
        )
    }

    /// One rule for the computer a transfer goes to and the models it offers.
    func destinationComputer(for room: String) -> String? {
        if let cloud = TaskHandoffCloudTarget(tag: room) { return destinationComputer(for: cloud.room) }
        if room == "local-mcp" { return localComputerId }
        return model.catalogEndpoint(forRoom: room)
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
        let previous = previousHandoffEvents
        handoffNotBefore = session.projectId.flatMap { model.meshSnapshots[$0]?.generatedAt } ?? 0
        Task {
            do {
                try await model.ensureProjectComputerNetwork(for: session, targetComputer: computer)
                guard observesHandoff else { return }
                let result = try await reader.handoff(
                    session, provider: destinationProvider, computer: computer,
                    targetModel: targetModel.isEmpty ? nil : targetModel,
                    comment: userComment.trimmingCharacters(in: .whitespacesAndNewlines),
                    checkpoint: checkpointUncommitted,
                    push: pushBranch && targetRoom != sourceRoom, cloud: cloudLaunch
                )
                if result.accepted {
                    await reader.refresh()
                    model.refreshMacCombinedCatalog()
                    await waitForHandoff(previousEvents: previous, computer: computer)
                }
                else { handoffError = result.error ?? L("The handoff was not accepted.") }
            } catch {
                handoffError = L("The local handoff service is unavailable. Check GrantTap MCP.")
            }
            submitting = false
        }
    }
    #endif
}

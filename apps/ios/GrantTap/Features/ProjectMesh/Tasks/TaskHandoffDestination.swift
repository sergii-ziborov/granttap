import SwiftUI

/// Where the Task goes: a computer and agent, or a provider's cloud runner
/// started by the computer that holds the Task, with the model and effort that
/// computer reports. Unknown models stay unknown; Automatic is always there.
extension TaskHandoffSheet {
    var cloudTarget: TaskHandoffCloudTarget? { TaskHandoffCloudTarget(tag: targetRoom) }

    var destinationProvider: String {
        cloudTarget?.provider ?? AgentIdentity.normalize(effectiveTargetProvider)
    }

    /// The models the destination computer itself reported for this provider.
    var modelCatalog: TurnModelCatalog {
        model.turnModelCatalog(agent: destinationProvider, endpointId: destinationComputer(for: effectiveTargetRoom))
    }

    /// Codex Cloud runs the environment's model; it takes no model from here.
    var modelOptions: [TurnModelOption] {
        cloudTarget?.provider == "codex" ? [] : modelCatalog.options
    }

    var effortChoices: [TurnEffort] {
        if cloudTarget?.provider == "codex" { return [] }
        return modelCatalog.efforts(for: targetModel.isEmpty ? nil : targetModel, agent: destinationProvider)
    }

    /// Said instead of a list nobody reported: Automatic leaves the choice to the provider.
    var modelAvailabilityNote: String? {
        guard cloudTarget?.provider != "codex", modelOptions.isEmpty else { return nil }
        guard destinationComputer(for: effectiveTargetRoom) != nil else {
            return L("This computer has not reported its models yet. Automatic lets the provider choose.")
        }
        return String(format: L("%@ on this computer has not reported a model list. Automatic lets it choose its own model."),
                      AgentIdentity.displayName(destinationProvider))
    }

    var destinationSection: some View {
        Section {
            Picker(L("Computer"), selection: $targetRoom) { computerOptions }
                .accessibilityIdentifier("handoff.computer")
            if cloudTarget == nil {
                Picker(L("Agent"), selection: $targetProvider) { agentOptions }
            }
            if cloudTarget?.provider != "codex" {
                Picker(L("Model"), selection: $targetModel) {
                    Text(L("Automatic")).tag("")
                    ForEach(modelOptions) { option in Text(option.label).tag(option.id) }
                }
                .accessibilityIdentifier("handoff.model")
            }
            if !effortChoices.isEmpty {
                Picker(L("Effort"), selection: $targetEffort) {
                    Text(L("Automatic")).tag("")
                    ForEach(effortChoices) { effort in Text(effort.label).tag(effort.rawValue) }
                }
                .accessibilityIdentifier("handoff.effort")
            }
            if cloudTarget?.provider == "codex" {
                TextField(L("Codex Cloud environment"), text: $cloudEnvironment)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("handoff.cloudEnvironment")
            }
        } header: {
            Text(L("Destination"))
        } footer: {
            destinationFooter
        }
        .onChange(of: targetProvider) { _ in targetModel = ""; targetEffort = "" }
        .onChange(of: targetRoom) { room in
            targetModel = ""
            targetEffort = ""
            if TaskHandoffCloudTarget(tag: room) != nil { pushBranch = true }
        }
        .onChange(of: targetModel) { _ in
            if !effortChoices.contains(where: { $0.rawValue == targetEffort }) { targetEffort = "" }
        }
    }

    private var destinationFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cloudTarget != nil
                 ? L("The computer that holds this Task starts the cloud run with its own CLI. GrantTap shows a link to it but cannot follow its progress.")
                 : sameAgentHere
                 ? L("Choose another agent or model, or another computer: this is where the Task already is.")
                 : staysHere
                    ? L("The Task continues here in a new worktree from the last commit.")
                    : L("The other computer needs the commit: push the branch, or make sure it can fetch it."))
            if let note = modelAvailabilityNote { Text(note) }
            if cloudTarget?.provider == "codex" {
                Text(L("Leave the environment empty to use the one this repository's recent Codex Cloud tasks ran in."))
            }
            if (!targetModel.isEmpty || !targetEffort.isEmpty) && cloudTarget == nil {
                Text(L("The destination keeps this Task’s title and visible conversation. Work starts with its first message."))
            }
        }
    }

    @ViewBuilder
    var transferContextSection: some View {
        Section {
            if cloudTarget != nil {
                Text(L("The cloud runner receives the Task Capsule: goal, status, branch and commit, your comment and the remaining work. The conversation itself stays on your computers."))
            } else {
                Text(L("GrantTap prepares the destination with the visible conversation, available attachments and project facts. Incomplete context stops the transfer."))
                Text(L("Use a separate branch or worktree on the destination computer. If no authorized checkout matches, the handoff fails safely in Needs You."))
            }
        }
    }

    /// Cloud runners appear only under the computer that holds the Task, and
    /// only when that computer says its installed CLI can start them. On the
    /// Mac, its own computer's report arrives through its paired room.
    var cloudTargets: [TaskHandoffCloudTarget] {
        guard let sourceRoom else { return [] }
        let integrations: [AgentIntegrationInfo]
        if sourceRoom == "local-mcp" {
            let local = localComputerId
            integrations = model.agentIntegrationsByRoom.values.first(where: { rows in
                rows.contains { $0.endpointId != nil && $0.endpointId == local }
            }) ?? []
        } else {
            integrations = model.agentIntegrationsByRoom[sourceRoom] ?? []
        }
        return TaskHandoffCloudTarget.available(in: integrations).map { .init(provider: $0, room: sourceRoom) }
    }

    var computerOptions: some View {
        Group {
            if let localComputerId {
                Text(String(format: L("%@ (this computer)"),
                            localComputerName ?? localComputerId)).tag("local-mcp")
            }
            ForEach(targets) { connection in
                Text(connection.id == sourceRoom
                     ? String(format: L("%@ (this computer)"), computerName(connection))
                     : computerName(connection)).tag(connection.id)
            }
            ForEach(cloudTargets, id: \.tag) { cloud in
                Text(cloud.label(computer: cloudComputerName(cloud.room))).tag(cloud.tag)
            }
        }
    }

    func cloudComputerName(_ room: String) -> String {
        if room == "local-mcp" { return localComputerName ?? localComputerId ?? room }
        return targets.first { $0.id == room }.map { computerName($0) } ?? room
    }

    var agentOptions: some View {
        Group {
            ForEach(AgentIdentity.composeIds.filter {
                model.agentMeshPreferences.isProviderEnabled($0)
            }, id: \.self) { provider in
                Text(AgentIdentity.displayName(provider)).tag(provider)
            }
        }
    }
}

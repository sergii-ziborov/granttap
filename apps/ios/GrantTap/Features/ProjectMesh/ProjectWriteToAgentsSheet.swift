import SwiftUI

/// Compact write path that reuses TaskComposer routing and TaskDelivery.
/// It is not a second chat product.
struct ProjectWriteToAgentsSheet: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("granttap.new-task.provider") private var savedProvider = ""
    @State private var text = ""
    @State private var provider: String
    @State private var computerId: String?
    @State private var workspace: String

    init(snapshot: ProjectMeshSnapshot, model: AppModel) {
        self.snapshot = snapshot
        self.model = model
        let enabled = model.agentMeshPreferences.enabledProviders
        let initial = TaskComposerRoutePresentation.defaultProvider(
            saved: UserDefaults.standard.string(forKey: "granttap.new-task.provider"),
            sessions: model.sessions.filter { $0.projectId == snapshot.projectId },
            enabledProviders: enabled
        )
        _provider = State(initialValue: initial)
        let folders = model.workspaceFolders(for: initial)
        let root = snapshot.project.repositoryRoot ?? ""
        if folders.contains(root) {
            _workspace = State(initialValue: root)
        } else {
            _workspace = State(initialValue: folders.first ?? root)
        }
        let names = Set(ProjectManagePresentation.endpointIds(snapshot))
        let match = model.connectionRegistry.connections.first { connection in
            names.contains(connection.id)
                || names.contains(connection.displayName)
                || names.contains(connection.lastMachineName)
        }
        _computerId = State(initialValue: match?.id ?? model.connectionRegistry.preferred?.id)
    }

    var computers: [TaskComposerComputerOption] {
        model.connectionRegistry.connections.map { connection in
            TaskComposerComputerOption(
                id: connection.id,
                name: TaskComposerRoutePresentation.computerName(
                    pairingLabel: connection.displayName,
                    publishedMachineName: connection.lastMachineName
                ),
                phase: model.snapshotForConnection(connection).phase
            )
        }
    }

    var selectedConnection: LinkedComputer? {
        if let computerId,
           let selected = model.connectionRegistry.connections.first(where: { $0.id == computerId }) {
            return selected
        }
        return model.connectionRegistry.preferred
    }

    var availability: TaskSendAvailability? {
        if model.demoMode { return nil }
        return TaskRoutePresentation.sendAvailability(
            agent: provider,
            route: model.chatComputerRoute(forRoomId: selectedConnection?.id)
        )
    }

    var body: some View {
        CompatNavigationStack {
            List {
                Section {
                    TextEditor(text: $text)
                        .font(.system(size: 17))
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("project.write-to-agents.text")
                } header: {
                    Text(L("Write to agents"))
                } footer: {
                    Text(L("Uses the existing task delivery path. Shared skills stay on the Project list and are not attached to this message."))
                }
                Section {
                    TaskComposerRoutePicker(
                        provider: $provider,
                        computerId: $computerId,
                        workspace: $workspace,
                        computers: computers,
                        workspaces: model.workspaceFolders(for: provider),
                        enabledProviders: model.agentMeshPreferences.enabledProviders
                    )
                } header: {
                    Text(L("Route"))
                }
                if let availability {
                    Section {
                        Text(availability.message)
                            .font(.caption)
                            .foregroundStyle(availability.blocksSending ? Theme.riskHigh : Theme.riskMed)
                    }
                }
            }
            .navigationTitle(L("Write to agents"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Send")) { send() }
                        .disabled(!canSend)
                        .accessibilityIdentifier("project.write-to-agents.send")
                }
            }
        }
    }

    var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && availability?.blocksSending != true
    }

    func send() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, canSend else { return }
        savedProvider = provider
        model.sendMessage(
            message,
            agent: provider,
            cwd: workspace.isEmpty ? nil : workspace,
            roomId: selectedConnection?.id
        )
        dismiss()
    }
}

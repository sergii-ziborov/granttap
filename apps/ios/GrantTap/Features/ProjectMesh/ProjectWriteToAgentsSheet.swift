import SwiftUI

/// Starts one new chat in this Project's repository.
/// It reuses TaskComposer routing and TaskDelivery; it is not a second product.
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
        if snapshot.execution?.mode == .pinned, let host = snapshot.execution?.targetEndpointId {
            _computerId = State(initialValue: host)
        } else {
            _computerId = State(initialValue: match?.id ?? model.connectionRegistry.preferred?.id)
        }
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
                        .accessibilityIdentifier("project.new-chat.text")
                } header: {
                    Text(L("New chat"))
                } footer: {
                    Text(L("Starts a new chat in this Project's repository. It is one task, not a broadcast to the chats already running."))
                }
                Section {
                    TaskComposerRoutePicker(
                        provider: $provider,
                        computerId: $computerId,
                        workspace: $workspace,
                        computers: computers,
                        workspaces: model.workspaceFolders(for: provider),
                        enabledProviders: model.agentMeshPreferences.enabledProviders,
                        pinnedEndpointId: snapshot.execution?.mode == .pinned
                            ? snapshot.execution?.targetEndpointId : nil
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
            .navigationTitle(L("New chat"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Send")) { send() }
                        .disabled(!canSend)
                        .accessibilityIdentifier("project.new-chat.send")
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

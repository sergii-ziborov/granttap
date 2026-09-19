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
    @State private var attachments: [AttachmentDraft] = []
    @State private var attachmentError: String?
    @FocusState private var focused: Bool

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
        let folders = ProjectWorkspacePresentation.folders(
            snapshot: snapshot, advertised: model.workspaceFolders(for: initial)
        )
        _workspace = State(initialValue: folders.first ?? "")
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

    var projectFolders: [String] {
        ProjectWorkspacePresentation.folders(
            snapshot: snapshot, advertised: model.workspaceFolders(for: provider)
        )
    }

    var computers: [TaskComposerComputerOption] {
        let names = Set(ProjectManagePresentation.endpointIds(snapshot))
        let linked = model.connectionRegistry.connections.filter { connection in
            names.isEmpty
                || names.contains(connection.id)
                || names.contains(connection.displayName)
                || names.contains(connection.lastMachineName)
        }
        return linked.map { connection in
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
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(L("Describe a new task…"))
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .focused($focused)
                        .modifier(ClearTextEditorBackground())
                        .accessibilityIdentifier("project.new-chat.text")
                }
                if let attachmentError {
                    Text(attachmentError)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.riskHigh)
                }
                AttachmentThumbnails(attachments: $attachments)
                    .onChange(of: attachments.map(\.id)) { _ in
                        model.preuploadAttachments(attachments, room: selectedConnection?.id)
                    }
                HStack(spacing: 8) {
                    AttachmentMenuButton(attachments: $attachments)
                    Spacer(minLength: 0)
                }
                if projectFolders.isEmpty {
                    Text(L("This Project has no folder on the selected computer."))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.riskHigh)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let availability {
                    Text(availability.message)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(availability.blocksSending ? Theme.riskHigh : Theme.riskMed)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TaskComposerRoutePicker(
                    provider: $provider,
                    computerId: $computerId,
                    workspace: $workspace,
                    computers: computers,
                    workspaces: projectFolders,
                    enabledProviders: model.agentMeshPreferences.enabledProviders,
                    pinnedEndpointId: snapshot.execution?.mode == .pinned
                        ? snapshot.execution?.targetEndpointId : nil
                )
                Text(L("Starts a new chat in this Project's repository. It is one task, not a broadcast to the chats already running."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Theme.bg)
            .navigationTitle(L("New chat"))
            .navigationBarTitleDisplayMode(.inline)
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
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
            && availability?.blocksSending != true
            && projectFolders.contains(workspace)
    }

    func send() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        do {
            try AttachmentDraft.validateTotal(attachments)
            attachmentError = nil
        } catch {
            attachmentError = error.localizedDescription
            return
        }
        savedProvider = provider
        model.sendMessage(
            message,
            agent: provider,
            cwd: workspace.isEmpty ? nil : workspace,
            attachments: attachments.map(\.payload),
            attachmentRefs: model.attachmentRefs(for: attachments, room: selectedConnection?.id),
            roomId: selectedConnection?.id,
            projectId: snapshot.projectId
        )
        dismiss()
    }
}

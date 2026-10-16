import SwiftUI

/// A Mesh-scoped task composer. The selected Mesh is context, never a routing picker.
struct ProjectNewTaskView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject var draft = ProjectTaskDraft()
    @State private var showDiscard = false
    @State private var closeRequested = false
    @FocusState var descriptionFocused: Bool
    @AppStorage("granttap.new-task.provider") var savedProvider = "codex"

    var currentSnapshot: ProjectMeshSnapshot { model.meshSnapshots[snapshot.projectId] ?? snapshot }
    var context: ProjectTaskCreationContext {
        var result = ProjectTaskCreationContext(snapshot: currentSnapshot,
            policy: model.projectGovernance[snapshot.projectId]?.policy?.execution ?? currentSnapshot.execution,
            enabledProviders: model.agentMeshPreferences.enabledProviders,
            rooms: model.meshComputerRoomByEndpointId)
        #if targetEnvironment(macCatalyst)
        if let reader = model.localMCPReader, reader.isReady { result.localEndpointId = reader.status?.endpointId }
        #endif
        return result
    }
    var catalog: TurnModelCatalog { context.catalog(provider: draft.provider, endpoint: draft.endpointId) }
    var selectedBinding: ProjectBindingSummary? { context.bindings(on: draft.endpointId).first { $0.bindingId == draft.bindingId } }

    var body: some View {
        ChatSheetNavigation(title: L("New Task"), doneIdentifier: "project.task.cancel",
            closeTitle: L("Cancel"), closeDisabled: draft.sending, dismissesPresentation: false,
            onClose: requestClose) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Label(model.projectDisplayName(currentSnapshot), systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("project.task.mesh")
                        #if targetEnvironment(macCatalyst)
                        HStack(alignment: .top, spacing: 20) {
                            taskEditor.frame(maxWidth: .infinity)
                            routeFields.frame(width: 320)
                        }
                        #else
                        taskEditor
                        routeFields
                        #endif
                        effortControl
                    }
                    .padding(20)
                }
                taskFooter
            }
            .background(Theme.bg)
        }
        #if targetEnvironment(macCatalyst)
        .frame(width: 780)
        .frame(minHeight: 560, idealHeight: 720, maxHeight: 740)
        .background(ProjectTaskMacDismissal(requested: closeRequested, onClosed: { onClose?() }))
        #endif
        .onAppear { draft.configure(context, preferredProvider: savedProvider) }
        .onChange(of: draft.provider) { _ in
            descriptionFocused = false
            draft.reconcile(context)
        }
        .onChange(of: draft.endpointId) { _ in
            descriptionFocused = false
            draft.reconcile(context)
            preupload()
        }
        .onChange(of: draft.model) { _ in descriptionFocused = false }
        .onChange(of: draft.attachments.map(\.id)) { _ in preupload() }
        .onChange(of: currentSnapshot.bindings) { _ in draft.reconcile(context) }
        .onChange(of: currentSnapshot.modelCatalog) { _ in draft.reconcile(context) }
        .interactiveDismissDisabled(draft.hasContent || draft.sending)
        .confirmationDialog(L("Discard this task?"), isPresented: $showDiscard, titleVisibility: .visible) {
            Button(L("Discard task"), role: .destructive, action: close)
            Button(L("Keep editing"), role: .cancel) {}
        }
    }

    private func requestClose() {
        guard !draft.sending else { return }
        if draft.hasContent { showDiscard = true } else { close() }
    }

    func close() {
        #if targetEnvironment(macCatalyst)
        closeRequested = true
        #else
        dismiss()
        onClose?()
        #endif
    }

    private func preupload() {
        guard !model.demoMode, draft.endpointId != context.localEndpointId,
              let room = context.rooms[draft.endpointId] else { return }
        model.preuploadAttachments(draft.attachments, room: room)
    }
}

import SwiftUI

struct ProjectNewTaskView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var provider = "codex"
    @State private var endpointId = ""
    @State private var bindingId = ""
    @State private var modelId = ""
    @State private var attachments: [AttachmentDraft] = []
    @State private var attachmentError: String?
    @State private var sending = false

    #if targetEnvironment(macCatalyst)
    private var isLocalRoute: Bool {
        model.localMCPReader?.status?.endpointId == endpointId
    }
    #else
    private var isLocalRoute: Bool { false }
    #endif

    private var policy: ProjectExecutionPolicy? {
        model.projectGovernance[snapshot.projectId]?.policy?.execution ?? snapshot.execution
    }

    private var endpoints: [(id: String, name: String)] {
        var names: [String: String] = [:]
        for binding in snapshot.bindings ?? [] where binding.available {
            names[binding.endpointId] = binding.displayName
        }
        return names.map { ($0.key, $0.value) }.sorted { $0.name < $1.name }
    }

    private var models: [ProjectAdvertisedModel] {
        (snapshot.modelCatalog ?? []).filter { $0.endpointId == endpointId }
            .flatMap(\.models).filter { $0.provider == provider }
            .sorted { $0.modelId < $1.modelId }
    }

    private var bindings: [ProjectBindingSummary] {
        (snapshot.bindings ?? []).filter {
            $0.endpointId == endpointId && $0.available && $0.localPathHint != nil
        }.sorted { $0.displayName < $1.displayName }
    }

    private var workspace: String? { bindings.first { $0.bindingId == bindingId }?.localPathHint }

    private var room: String? { model.meshComputerRoomByEndpointId[endpointId] }

    var body: some View {
        CompatNavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(snapshot.project.name)
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                editor
                routingPickers
                actions
            }
            .padding(16)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(L("New Task"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
        .onAppear(perform: applyDefaults)
        .onChange(of: endpointId) { _ in
            chooseBinding()
            chooseAvailableModel()
        }
        .onChange(of: provider) { _ in chooseAvailableModel() }
        .onChange(of: attachments.map(\.id)) { _ in
            model.preuploadAttachments(attachments, room: room)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            AttachmentThumbnails(attachments: $attachments)
            TextEditor(text: $text)
                .font(.system(size: 17))
                .frame(maxHeight: .infinity)
                .padding(10)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
            if let attachmentError {
                Text(attachmentError).font(.caption).foregroundStyle(Theme.riskHigh)
            }
        }
    }

    private var routingPickers: some View {
        VStack(spacing: 4) {
            Picker(L("Agent"), selection: $provider) {
                ForEach(model.agentMeshPreferences.enabledProviders.sorted(), id: \.self) {
                    Text(AgentIdentity.displayName($0)).tag($0)
                }
            }
            Picker(L("Computer"), selection: $endpointId) {
                ForEach(endpoints, id: \.id) { Text($0.name).tag($0.id) }
            }
            Picker(L("Workspace"), selection: $bindingId) {
                ForEach(bindings, id: \.bindingId) { Text($0.displayName).tag($0.bindingId) }
            }
            Picker(L("Model"), selection: $modelId) {
                Text(L("Automatic")).tag("")
                ForEach(models) { Text($0.label ?? $0.modelId).tag($0.modelId) }
            }
            if let routeProblem {
                Text(routeProblem).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var actions: some View {
        HStack {
            AttachmentMenuButton(attachments: $attachments)
            Spacer()
            Button(action: send) {
                if sending { ProgressView() }
                else { Text(L("Create Task")) }
            }
            .buttonStyle(.borderedProminent).disabled(!canSend)
        }
    }

    private var canSend: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
            && !endpointId.isEmpty && workspace != nil && (room != nil || isLocalRoute)
            && !sending
            && routeProblem == nil
    }

    private func applyDefaults() {
        endpointId = policy?.targetEndpointId ?? endpoints.first?.id ?? ""
        chooseBinding()
        provider = policy?.defaultProvider
            ?? models.first?.provider
            ?? model.agentMeshPreferences.enabledProviders.first
            ?? "codex"
        modelId = policy?.defaultModel ?? ""
        chooseAvailableModel()
    }

    private func chooseBinding() {
        if !bindings.contains(where: { $0.bindingId == bindingId }) {
            bindingId = bindings.first?.bindingId ?? ""
        }
    }

    private var routeProblem: String? {
        if policy?.mode == "pinned" && policy?.targetEndpointId == endpointId {
            switch policy?.hostGrantStatus {
            case "applied": break
            case "unavailable": return L("The pinned execution host is unavailable.")
            default: return L("The pinned execution host has not confirmed its grant.")
            }
        }
        if room == nil && !isLocalRoute {
            return L("This computer is not connected to the Mesh.")
        }
        if workspace == nil { return L("Choose a workspace registered on this computer.") }
        return nil
    }

    private func chooseAvailableModel() {
        guard !modelId.isEmpty, models.contains(where: { $0.modelId == modelId }) else {
            modelId = policy?.defaultProvider == provider ? policy?.defaultModel ?? "" : ""
            if !models.contains(where: { $0.modelId == modelId }) { modelId = "" }
            return
        }
    }

    private func send() {
        do { try AttachmentDraft.validateTotal(attachments) }
        catch { attachmentError = error.localizedDescription; return }
        #if targetEnvironment(macCatalyst)
        if isLocalRoute {
            guard let reader = model.localMCPReader else { return }
            sending = true
            Task {
                do {
                    let result = try await reader.createTask(
                        projectId: snapshot.projectId, bindingId: bindingId,
                        endpointId: endpointId, provider: provider,
                        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                        model: modelId.isEmpty ? nil : modelId, attachments: attachments
                    )
                    if result.created {
                        await reader.refresh()
                        MacLocalProjection.apply(reader.meshSnapshots, to: model)
                        dismiss()
                    } else {
                        attachmentError = result.error ?? L("Could not create this Task.")
                    }
                } catch {
                    attachmentError = L("Could not create this Task.")
                }
                sending = false
            }
            return
        }
        #endif
        model.sendMessage(
            text.trimmingCharacters(in: .whitespacesAndNewlines), agent: provider,
            cwd: workspace, attachments: attachments.map(\.payload),
            attachmentRefs: model.attachmentRefs(for: attachments, room: room),
            roomId: room, projectId: snapshot.projectId,
            model: modelId.isEmpty ? nil : modelId
        )
        dismiss()
    }
}

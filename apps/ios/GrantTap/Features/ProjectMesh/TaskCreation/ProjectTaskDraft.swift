import Foundation

struct ProjectTaskCreationRequest {
    let operationId: UUID
    let projectId: String
    let endpointId: String
    let bindingId: String
    let workspace: String
    let provider: String
    let text: String
    let model: String?
    let effort: String?
    let attachments: [AttachmentDraft]
}

@MainActor
final class ProjectTaskDraft: ObservableObject {
    @Published var text = ""
    @Published var provider = "codex"
    @Published var endpointId = ""
    @Published var bindingId = ""
    @Published var model: TurnModel?
    @Published var effort: TurnEffort?
    @Published var attachments: [AttachmentDraft] = []
    @Published var error: String?
    @Published var sending = false
    private var initialized = false
    private var lastSignature: [String]?
    private var operationId = UUID()

    var hasContent: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty }

    func configure(_ context: ProjectTaskCreationContext, preferredProvider: String? = nil) {
        guard !initialized else { reconcile(context); return }
        initialized = true
        provider = context.policy?.defaultProvider.flatMap { context.providers.contains($0) ? $0 : nil }
            ?? preferredProvider.flatMap { context.providers.contains($0) ? $0 : nil }
            ?? (context.providers.contains("codex") ? "codex" : context.providers.first ?? "")
        endpointId = context.policy?.targetEndpointId.flatMap { context.endpointIds.contains($0) ? $0 : nil }
            ?? context.localEndpointId.flatMap { context.endpointIds.contains($0) ? $0 : nil }
            ?? context.endpointIds.first ?? ""
        model = context.policy?.defaultModel.flatMap(TurnModel.init(rawValue:))
        reconcile(context)
    }

    func reconcile(_ context: ProjectTaskCreationContext) {
        if !context.providers.contains(provider) { provider = context.providers.first ?? "" }
        if !context.endpointIds.contains(endpointId) { endpointId = context.endpointIds.first ?? "" }
        let bindings = context.bindings(on: endpointId)
        if !bindings.contains(where: { $0.bindingId == bindingId }) { bindingId = bindings.first?.bindingId ?? "" }
        let catalog = context.catalog(provider: provider, endpoint: endpointId)
        if let model, !catalog.options.contains(where: { $0.model == model }) { self.model = nil }
        if let effort, !catalog.efforts(for: model?.id, agent: provider).contains(effort) { self.effort = nil }
        error = nil
    }

    func problem(_ context: ProjectTaskCreationContext) -> String? {
        if !context.providers.contains(provider) { return L("Choose an enabled provider.") }
        if text.utf16.count > 8_000 { return L("Keep the task description within 8,000 characters.") }
        return context.routeProblem(endpoint: endpointId, bindingId: bindingId)
    }

    func canCreate(_ context: ProjectTaskCreationContext) -> Bool {
        hasContent && !sending && problem(context) == nil
    }

    /// A confirmed refusal may be retried as a new operation. An uncertain
    /// transport failure retains its ID so a retry cannot create a duplicate.
    func confirmedFailure() { lastSignature = nil }

    func request(_ context: ProjectTaskCreationContext) throws -> ProjectTaskCreationRequest {
        guard canCreate(context), let binding = context.bindings(on: endpointId).first(where: { $0.bindingId == bindingId }),
              let workspace = binding.localPathHint else { throw ProjectTaskDraftError.invalidRoute }
        try AttachmentDraft.validateTotal(attachments)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wire = TurnOverrides(model: model, effort: effort).wire(for: provider,
            catalog: context.catalog(provider: provider, endpoint: endpointId))
        let signature = [context.snapshot.projectId, endpointId, bindingId, provider, text,
                         wire.model ?? "", wire.effort ?? ""] + attachments.map { $0.id.uuidString }
        if lastSignature != signature { operationId = UUID(); lastSignature = signature }
        return ProjectTaskCreationRequest(operationId: operationId, projectId: context.snapshot.projectId,
            endpointId: endpointId, bindingId: bindingId, workspace: workspace, provider: provider, text: text,
            model: wire.model, effort: wire.effort, attachments: attachments)
    }
}

enum ProjectTaskDraftError: LocalizedError {
    case invalidRoute
    var errorDescription: String? { L("Choose a computer and workspace in this Mesh.") }
}

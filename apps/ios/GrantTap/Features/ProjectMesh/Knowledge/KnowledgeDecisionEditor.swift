import SwiftUI

struct KnowledgeDecisionEditor: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    let superseded: ProjectKnowledgeRecord?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var writes = KnowledgeWriteCoordinator.shared
    @State private var taskId: String
    @State private var content: String
    @State private var submittedId: String?
    @State private var localError: String?
    @State private var showRetry = false
    @State private var retryCount = 0

    init(snapshot: ProjectMeshSnapshot, model: AppModel,
         superseded: ProjectKnowledgeRecord? = nil) {
        self.snapshot = snapshot
        self.model = model
        self.superseded = superseded
        _taskId = State(initialValue: superseded?.taskId ?? snapshot.tasks.first?.taskId ?? "")
        _content = State(initialValue: superseded?.content ?? "")
    }

    var body: some View {
        CompatNavigationStack {
            Form {
                Section {
                    if let superseded {
                        Text(superseded.content).foregroundStyle(Theme.muted)
                    }
                    Picker(L("Task"), selection: $taskId) {
                        ForEach(snapshot.tasks) { task in
                            Text(task.title).tag(task.taskId)
                        }
                    }
                    .disabled(superseded != nil)
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                        .accessibilityIdentifier("knowledge.decision.content")
                } header: {
                    Text(superseded == nil ? L("Verified decision") : L("Correct the decision"))
                } footer: {
                    Text(L("This statement is stored in Mesh memory with your source and Task. A correction replaces the old decision in future context packets."))
                }
                if superseded != nil {
                    Section {
                        Button(L("Withdraw this decision"), role: .destructive) {
                            content = L("The previous decision was withdrawn by the user.")
                            submit()
                        }
                    }
                }
                if let localError {
                    Section { Text(localError).foregroundStyle(Theme.riskHigh) }
                }
                if let submittedId, writes.pending.contains(submittedId) {
                    Section {
                        ProgressView(L("Waiting for Memory confirmation…"))
                        if showRetry {
                            Button(L("Retry the same decision")) {
                                if writes.retry(submittedId, model: model) {
                                    showRetry = false
                                    retryCount += 1
                                } else {
                                    localError = L("The request status is unknown. Check Knowledge before recording it again.")
                                }
                            }
                        }
                    }
                }
                if let submittedId, let result = writes.results[submittedId],
                   result.status == "rejected" {
                    Section {
                        Text(result.reason ?? L("The computer rejected this decision."))
                            .foregroundStyle(Theme.riskHigh)
                    }
                }
            }
            .navigationTitle(superseded == nil ? L("Record decision") : L("Correct decision"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) { submit() }
                        .disabled(taskId.isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || content.count > 4_096 || submittedId.map(writes.pending.contains) == true)
                }
            }
            .onChange(of: writes.results.count) { _ in
                guard let submittedId, writes.results[submittedId]?.status == "recorded" else { return }
                dismiss()
            }
            .task(id: "\(submittedId ?? "")-\(retryCount)") {
                guard submittedId != nil else { return }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if !Task.isCancelled { showRetry = true }
            }
        }
    }

    private func submit() {
        localError = nil
        showRetry = false
        submittedId = writes.submit(model: model, projectId: snapshot.projectId,
                                    taskId: taskId, content: content,
                                    repositoryId: superseded?.repositoryId,
                                    supersedesRecordId: superseded?.recordId)
        if submittedId == nil {
            localError = L("No Live computer with this Mesh binding is available.")
        }
    }
}

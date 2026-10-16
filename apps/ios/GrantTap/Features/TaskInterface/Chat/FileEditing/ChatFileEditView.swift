import SwiftUI

@MainActor
struct ChatFileEditView: View {
    @ObservedObject var model: AppModel
    let session: SessionInfo
    @ObservedObject var buffer: TaskFileEditDraft
    private var snapshot: TaskWorkspaceSnapshot { buffer.snapshot }
    @State private var reviewing = false
    @State private var diff: TaskFileEditDiff?

    init(model: AppModel, session: SessionInfo, buffer: TaskFileEditDraft) {
        self.model = model
        self.session = session
        self.buffer = buffer
    }

    private var changed: Bool { buffer.changed }
    private var tooLarge: Bool { buffer.text.utf8.count > TaskFileEditRequest.maxTextBytes }
    private var row: OutgoingDelivery? { model.deliveries.first { $0.id == buffer.deliveryId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.path).font(Theme.mono(11)).foregroundStyle(Theme.muted)
                .textSelection(.enabled).padding(16)
            if reviewing, let diff {
                if diff.truncated {
                    Text(L("The diff preview is shortened. The request includes the complete edit."))
                        .font(.caption).foregroundStyle(Theme.muted).padding(.horizontal, 16)
                }
                ChatFileDiffViewport { DiffPreviewView(text: diff.text, wrapLines: false) }
                    .accessibilityIdentifier("chat.file-edit.diff")
            } else {
                TextEditor(text: $buffer.text).font(Theme.mono(12)).foregroundStyle(Theme.ink)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .padding(.horizontal, 12).disabled(buffer.deliveryId != nil)
                    .accessibilityIdentifier("chat.file-edit.editor")
            }
            actions
        }
        .foregroundStyle(Theme.ink).background(Theme.bg)
        .interactiveDismissDisabled(changed && buffer.deliveryId == nil)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            if buffer.deliveryId != nil {
                Label(row.flatMap(RelayTaskQueueStatus.title) ?? L("Request queued"), systemImage: "tray.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("chat.file-edit.status")
                if let error = row?.error {
                    Text(error).font(.caption).foregroundStyle(Theme.riskHigh)
                }
                Text(L("Track delivery or retry in this chat's Queue."))
                    .font(.caption).foregroundStyle(Theme.muted)
            } else {
                Text(L("Your edits will be sent as a request to this Task's agent. The agent checks the current file before applying them."))
                    .font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                if let failure = tooLarge ? TaskFileEditRequest.Failure.tooLarge.errorDescription : buffer.failure {
                    Text(failure).font(.caption).foregroundStyle(Theme.riskHigh)
                }
                HStack {
                    if reviewing {
                        Button(L("Keep editing")) { reviewing = false }
                            .accessibilityIdentifier("chat.file-edit.back")
                        Spacer()
                        Button(L("Send edit request"), action: send)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("chat.file-edit.send")
                    } else {
                        Spacer()
                        Button(L("Review changes")) {
                            diff = TaskFileEditDiff(original: snapshot.text ?? "", proposed: buffer.text, path: snapshot.path)
                            reviewing = true
                        }
                        .buttonStyle(.borderedProminent).disabled(!changed || tooLarge)
                        .accessibilityIdentifier("chat.file-edit.review")
                    }
                }
            }
        }
        .padding(16)
    }

    private func send() {
        guard buffer.deliveryId == nil else { return }
        do {
            buffer.deliveryId = try model.queueTaskFileEdit(snapshot: snapshot, replacement: buffer.text, to: session)
            if buffer.deliveryId == nil { buffer.failure = L("The edit request could not be queued. Your draft has been kept.") }
        } catch { buffer.failure = error.localizedDescription }
    }

}

import SwiftUI

struct ChatQueuedMessagesSheet: View {
    @ObservedObject var model: AppModel
    let session: SessionInfo
    @Environment(\.dismiss) private var dismiss
    @State private var preview: AttachmentPreviewFile?
    @State private var previewError: String?
    @State private var confirmingRetry: String?
    private var rows: [OutgoingDelivery] { model.chatQueuedMessages(for: session) }

    var body: some View {
        ChatSheetNavigation(title: L("Message queue"), doneIdentifier: "chat.queue.done", onClose: { dismiss() }) {
            List {
                ForEach(rows) { row in messageRow(row) }
            }
            .accessibilityIdentifier("chat.queue.rows")
            .background(Theme.bg)
            .onChange(of: rows.count) { count in if count == 0 { dismiss() } }
            .alert(L("Run this message again?"), isPresented: Binding(
                get: { confirmingRetry != nil }, set: { if !$0 { confirmingRetry = nil } }
            )) {
                Button(L("Cancel"), role: .cancel) { confirmingRetry = nil }
                Button(L("Run again")) {
                    if let confirmingRetry { model.sendChatQueuedMessageNow(confirmingRetry) }
                    confirmingRetry = nil
                }
            } message: {
                Text(L("The previous attempt may have changed files. Check the chat before starting another attempt."))
            }
            .modifier(AttachmentPreviewPresentation(file: $preview))
            .alert(L("Could not open preview"), isPresented: Binding(
                get: { previewError != nil }, set: { if !$0 { previewError = nil } }
            )) { Button(L("OK"), role: .cancel) {} } message: { Text(previewError ?? "") }
        }
    }

    private func messageRow(_ row: OutgoingDelivery) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: DeliveryTick.forState(row.state).systemImage)
                Text(RelayTaskQueueStatus.title(row) ?? DeliveryTick.forState(row.state).accessibilityLabel).font(.caption.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(row.state == .failed ? Theme.riskHigh : Theme.muted)
            if row.chatQueue?.relayManaged == true {
                if let due = row.chatQueue?.notBefore, due > Date().timeIntervalSince1970 * 1_000 {
                    Text(Date(timeIntervalSince1970: due / 1_000), style: .date)
                        .font(.caption).foregroundStyle(Theme.muted)
                    Text(Date(timeIntervalSince1970: due / 1_000), style: .time)
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Text(row.text.isEmpty ? L("Attachments") : row.text)
                .font(.subheadline).foregroundStyle(Theme.ink).lineLimit(4)
                .accessibilityIdentifier("chat.queue.text.\(row.id)")
            if let error = row.error {
                Text(error).font(.caption).foregroundStyle(Theme.riskHigh)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !row.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(row.attachments.enumerated()), id: \.offset) { _, attachment in
                            Button(attachment.name) { open(attachment) }
                                .font(.caption).lineLimit(1)
                                .accessibilityLabel(String(format: L("Preview %@"), attachment.name))
                        }
                    }
                }
            }
            HStack {
                Button {
                    if row.relayJob?.serverState == .failed { confirmingRetry = row.id }
                    else { model.sendChatQueuedMessageNow(row.id) }
                } label: {
                    Label(L(actionTitle(row)), systemImage: "arrow.up")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("chat.queue.send.\(row.id)")
                .disabled(!model.canSendChatQueuedMessageNow(row) || session.isPaused)
                Spacer()
                Button { model.cancelChatQueuedMessage(row.id) } label: {
                    Image(systemName: "trash").frame(width: 44, height: 44)
                }
                .accessibilityLabel(L("Cancel queued message"))
                .accessibilityIdentifier("chat.queue.cancel.\(row.id)")
                .disabled(!ChatMessageQueuePolicy.canCancel(row))
            }
            if row.chatQueue?.relayManaged != true, row.chatQueue?.waiting == false, row.state != .failed {
                Text(L("Check delivery refreshes this chat's history without sending the message again."))
                    .font(.caption).foregroundStyle(Theme.muted)
            } else if row.relayJob?.serverState == .accepted {
                Text(L("The computer accepted this message. Continue in the chat to pause the agent."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .pointerButtonStyle()
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private func actionTitle(_ row: OutgoingDelivery) -> String {
        if row.state == .failed { return "Retry" }
        return row.chatQueue?.relayManaged != true && row.chatQueue?.waiting == false ? "Check delivery" : "Send now"
    }

    private func open(_ attachment: UserAttachment) {
        guard let data = Data(base64Encoded: attachment.data) else { return }
        do { preview = try AttachmentPreviewFile(
            AttachmentDraft(name: attachment.name, mimeType: attachment.mimeType, data: data)) }
        catch { previewError = error.localizedDescription }
    }
}

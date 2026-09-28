import SwiftUI

struct ChatMessageQueueBar: View {
    @EnvironmentObject var model: AppModel
    let session: SessionInfo
    @State private var expanded = true
    @State private var preview: AttachmentPreviewFile?
    @State private var previewError: String?

    private var rows: [OutgoingDelivery] { model.chatQueuedMessages(for: session) }

    var body: some View {
        if !rows.isEmpty {
            VStack(spacing: 0) {
                Button { expanded.toggle() } label: {
                    HStack {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        Text(String(format: L("Queue · %d"), rows.count))
                        Spacer()
                        Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 16).frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.queue")
                if expanded {
                    ScrollView {
                        VStack(spacing: 0) { ForEach(rows) { row in messageRow(row) } }
                    }
                    .frame(height: min(CGFloat(rows.count) * 60, 180))
                    .accessibilityIdentifier("chat.queue.rows")
                }
            }
            .background(Theme.surface)
            .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
            .modifier(AttachmentPreviewPresentation(file: $preview))
            .alert(L("Could not open preview"), isPresented: Binding(
                get: { previewError != nil }, set: { if !$0 { previewError = nil } }
            )) { Button(L("OK"), role: .cancel) {} } message: { Text(previewError ?? "") }
        }
    }

    private func messageRow(_ row: OutgoingDelivery) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.state == .sending ? "arrow.up.circle" : "clock")
                .foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.text.isEmpty ? L("Attachments") : row.text)
                    .font(.system(size: 14)).foregroundStyle(Theme.ink).lineLimit(1)
                    .accessibilityIdentifier("chat.queue.text.\(row.id)")
                if let error = row.error {
                    Text(error).font(.system(size: 10)).foregroundStyle(Theme.riskHigh).lineLimit(1)
                } else if !row.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(row.attachments.enumerated()), id: \.offset) { _, attachment in
                                Button(attachment.name) { open(attachment) }
                                    .font(.system(size: 10)).lineLimit(1)
                                    .accessibilityLabel(String(format: L("Preview %@"), attachment.name))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.sendChatQueuedMessageNow(row.id) } label: {
                Image(systemName: "arrow.up").frame(width: 34, height: 40)
            }
            .accessibilityLabel(L("Send now"))
            .accessibilityIdentifier("chat.queue.send.\(row.id)")
            .disabled(!ChatMessageQueuePolicy.canCancel(row) || session.isPaused
                || row.awaitingSessionRemap == true)
            Button { model.cancelChatQueuedMessage(row.id) } label: {
                Image(systemName: "trash").frame(width: 34, height: 40)
            }
            .accessibilityLabel(L("Cancel queued message"))
            .accessibilityIdentifier("chat.queue.cancel.\(row.id)")
            .disabled(!ChatMessageQueuePolicy.canCancel(row))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).frame(height: 60)
        .accessibilityElement(children: .contain)
    }

    private func open(_ attachment: UserAttachment) {
        guard let data = Data(base64Encoded: attachment.data) else { return }
        do { preview = try AttachmentPreviewFile(
            AttachmentDraft(name: attachment.name, mimeType: attachment.mimeType, data: data)) }
        catch { previewError = error.localizedDescription }
    }
}

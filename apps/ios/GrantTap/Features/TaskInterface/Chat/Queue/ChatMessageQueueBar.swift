import SwiftUI

/// The queue is a floating control; its retained messages open in a sheet.
struct ChatMessageQueueBar: View {
    @EnvironmentObject var model: AppModel
    let session: SessionInfo
    @State private var showing = false
    private var rows: [OutgoingDelivery] { model.chatQueuedMessages(for: session) }

    var body: some View {
        if !rows.isEmpty {
            Button { showing = true } label: {
                Label(String(format: L("Queue · %d"), rows.count),
                      systemImage: rows.contains { $0.state == .failed }
                        ? "exclamationmark.circle.fill" : "text.line.first.and.arrowtriangle.forward")
                    .foregroundStyle(rows.contains { $0.state == .failed } ? Theme.riskHigh : Theme.ink)
            }
            .buttonStyle(ChatAccessoryPillStyle())
            .accessibilityIdentifier("chat.queue")
            .sheet(isPresented: $showing) {
                ChatQueuedMessagesSheet(model: model, session: session)
            }
        }
    }
}

import SwiftUI

extension TaskChatView {
    var queuesNewMessages: Bool {
        currentSession.state == "working" || currentSession.isPaused
            || !model.chatQueuedMessages(for: currentSession).isEmpty
    }

    func send() {
        if replyRequestId == nil && queuesNewMessages { queueDraft() }
        else { sendImmediately() }
    }

    func queueDraft() {
        guard replyRequestId == nil else { sendImmediately(); return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        do { try AttachmentDraft.validateTotal(attachments) }
        catch { attachmentError = error.localizedDescription; return }
        #if targetEnvironment(macCatalyst)
        if model.usesLocalMCP(for: currentSession), selectedMcp != nil || selectedSkill != nil {
            localSendError = L("Explicit MCP and skill routing is not available for local Task replies yet.")
            return
        }
        #endif
        guard model.queueChatMessage(text, to: currentSession,
            attachments: attachments.map(\.payload), preferredMcp: selectedMcp,
            skill: selectedSkill, overrides: model.turnOverrides.resolved(
                sessionId: chatSessionId, agent: currentSession.agent)) else {
            attachmentError = L("Message was not sent because the reliable outbox is full or the message is too large.")
            return
        }
        draft = ""
        attachments = []
        selectedMcp = nil
        selectedSkill = nil
        attachmentError = nil
        // Queueing is allowed while offline or paused. Only a confirmed idle
        // observation and an available transport can release it automatically.
        model.resumeChatQueues(observed: [currentSession])
    }
}

struct ComposerQueueButton: View {
    let add: () -> Void
    let sendNow: () -> Void

    var body: some View {
        Menu {
            Button(action: add) { Label(L("Add to queue"), systemImage: "text.badge.plus") }
                .accessibilityIdentifier("composer.queue.add")
            Button(action: sendNow) { Label(L("Send now"), systemImage: "arrow.up") }
                .accessibilityIdentifier("composer.queue.sendNow")
        } label: {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 34, height: 34)
        }
        .accessibilityLabel(L("Message queue"))
        .accessibilityIdentifier("composer.queue")
    }
}

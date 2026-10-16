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

    func queueDraft() { _ = queueDraft(at: nil) }

    func queueDraft(at scheduledDate: Date?) -> Bool {
        guard !transferRequiresConfirmation else { return false }
        guard replyRequestId == nil else { sendImmediately(); return false }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return false }
        do { try AttachmentDraft.validateTotal(attachments) }
        catch { attachmentError = error.localizedDescription; return false }
        guard model.queueChatMessage(text, to: currentSession,
            attachments: attachments.map(\.payload), preferredMcp: selectedMcp,
            skill: selectedSkill, overrides: model.turnOverrides.resolved(
                sessionId: chatSessionId, agent: currentSession.agent), notBefore: scheduledDate) else {
            attachmentError = L("Message was not sent because the reliable outbox is full or the message is too large.")
            return false
        }
        draft = ""
        attachments = []
        selectedMcp = nil
        selectedSkill = nil
        attachmentError = nil
        // Queueing is allowed while offline or paused. Only a confirmed idle
        // observation and an available transport can release it automatically.
        model.resumeChatQueues(observed: [currentSession])
        return true
    }
}

struct ComposerQueueButton: View {
    let add: () -> Void
    let sendNow: () -> Void
    var schedule: (() -> Void)? = nil

    var body: some View {
        Menu {
            Button(action: add) { Label(L("Add to queue"), systemImage: "text.badge.plus") }
                .accessibilityIdentifier("composer.queue.add")
            if let schedule {
                Button(action: schedule) { Label(L("Schedule message…"), systemImage: "clock") }
                    .accessibilityIdentifier("composer.queue.schedule")
            }
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

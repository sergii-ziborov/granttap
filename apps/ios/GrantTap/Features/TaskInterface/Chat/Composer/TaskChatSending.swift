import SwiftUI

extension TaskChatView {
    func sendImmediately() {
        guard !transferRequiresConfirmation else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let requestId = replyRequestId {
            guard !text.isEmpty else { return }
            model.answerQuestion(requestId, text)
            replyRequestId = nil
            draft = ""
            attachments = []
            return
        }
        guard !text.isEmpty || !attachments.isEmpty else { return }
        guard chatSendAvailability?.blocksSending != true else { return }
        #if targetEnvironment(macCatalyst)
        if let reader = model.localMCPReader, model.usesLocalTaskDelivery(for: currentSession) {
            guard !localSending else { return }
            localSending = true
            localSendError = nil
            Task {
                defer { localSending = false }
                do {
                    let options = model.turnOverrides.resolved(sessionId: chatSessionId, agent: currentSession.agent)
                    let wire = options.wire(for: currentSession.agent,
                        catalog: model.turnModelCatalog(agent: currentSession.agent, session: currentSession),
                        currentModel: currentSession.model)
                    let result = try await reader.send(text, to: currentSession, attachments: attachments,
                        model: wire.model,
                        effort: wire.effort, preferredMcp: selectedMcp, skill: selectedSkill,
                        permissionMode: wire.permissionMode)
                    if result.accepted {
                        draft = ""
                        attachments = []
                        selectedMcp = nil
                        selectedSkill = nil
                        await loadLocalConversation()
                    } else {
                        localSendError = result.error ?? L("Could not send to this Task.")
                    }
                } catch {
                    localSendError = L("Could not send to this Task. Retry after checking the Mac connection.")
                }
            }
            return
        }
        #endif
        do {
            try AttachmentDraft.validateTotal(attachments)
            attachmentError = nil
        } catch {
            attachmentError = error.localizedDescription
            return
        }
        let room = model.sourceRoom(forSessionId: chatSessionId)
        model.sendMessage(text, agent: session.agent, sessionId: chatSessionId,
                          attachments: attachments.map(\.payload),
                          attachmentRefs: model.attachmentRefs(for: attachments, room: room),
                          preferredMcp: selectedMcp,
                          skill: selectedSkill,
                          overrides: model.turnOverrides.resolved(
                              sessionId: chatSessionId,
                              agent: currentSession.agent
                          ))
        draft = ""
        attachments = []
        attachmentError = nil
        selectedMcp = nil
        selectedSkill = nil
    }

    var chatSendAvailability: TaskSendAvailability? {
        if suppressAvailabilityForDebugCapture || model.demoMode { return nil }
        if currentSession.isPaused {
            return TaskSendAvailability(
                message: L("This chat is paused. Resume to send."),
                blocksSending: true
            )
        }
        #if targetEnvironment(macCatalyst)
        if model.usesLocalTaskDelivery(for: currentSession) { return nil }
        #endif
        return TaskRoutePresentation.sendAvailability(
            agent: currentSession.agent,
            route: model.chatComputerRoute(forSessionId: chatSessionId)
        )
    }
}

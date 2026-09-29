import SwiftUI

extension TaskChatView {
    func sendImmediately() {
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
        if let reader = model.localMCPReader, model.usesLocalMCP(for: currentSession) {
            guard !localSending else { return }
            guard selectedMcp == nil, selectedSkill == nil else {
                localSendError = L("Explicit MCP and skill routing is not available for local Task replies yet.")
                return
            }
            localSending = true
            localSendError = nil
            Task {
                defer { localSending = false }
                do {
                    let options = model.turnOverrides.resolved(sessionId: chatSessionId, agent: currentSession.agent)
                    let result = try await reader.send(text, to: currentSession, attachments: attachments,
                        model: options.wire(for: currentSession.agent).model)
                    if result.accepted {
                        draft = ""
                        attachments = []
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
        #if targetEnvironment(macCatalyst)
        if model.usesLocalMCP(for: currentSession) {
            return nil
        }
        #endif
        if currentSession.isPaused {
            return TaskSendAvailability(
                message: L("Paused from this phone: the computer refuses its tool calls. Resume to send."),
                blocksSending: true
            )
        }
        return TaskRoutePresentation.sendAvailability(
            agent: currentSession.agent,
            route: model.chatComputerRoute(forSessionId: chatSessionId)
        )
    }
}

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

extension TaskChatView {
    /// Nested agent conversations indent, but only so far: past four levels the
    /// text column becomes unreadable on a phone.
    static func threadIndent(_ visualDepth: Int) -> CGFloat {
        CGFloat(max(0, min(visualDepth - 1, 4))) * 16
    }

    /// Reads and writes this chat's own choice, so it survives closing the screen.
    var chatModelBinding: Binding<TurnModel?> {
        Binding(
            get: { model.turnOverrides.chatOverrides(chatSessionId).model },
            set: { picked in
                var current = model.turnOverrides.chatOverrides(chatSessionId)
                current.model = picked
                model.turnOverrides.setChatOverrides(current, for: chatSessionId)
            }
        )
    }

    var chatPermissionBinding: Binding<TurnPermissionMode?> {
        Binding(
            get: { model.turnOverrides.chatOverrides(chatSessionId).permissionMode },
            set: { picked in
                var current = model.turnOverrides.chatOverrides(chatSessionId)
                current.permissionMode = picked
                model.turnOverrides.setChatOverrides(current, for: chatSessionId)
            }
        )
    }

    func toggleCapability(_ row: ChatCapabilityRow) {
        switch row.kind {
        case .mcp:
            model.setSessionMcpAllowed(chatSessionId, serverName: row.name,
                                       allowed: row.allowed == false)
        case .skill:
            model.setSessionSkillAllowed(chatSessionId, skillName: row.name,
                                         allowed: row.allowed == false)
        case .cli:
            model.setSessionShellAllowed(chatSessionId, allowed: row.allowed == false)
        }
    }

    var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let availability = chatSendAvailability {
                Text(availability.message)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(availability.blocksSending ? Theme.riskHigh : Theme.riskMed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let attachmentError {
                Text(attachmentError)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.riskHigh)
            }
            MessageRoutingStrip(selectedMcp: $selectedMcp, selectedSkill: $selectedSkill)
            if dictator.isRecording || dictator.isStarting {
                ListeningStatus(isStarting: dictator.isStarting, language: dictator.detectedLanguage)
            }
            if let error = dictator.errorText {
                Text(error).font(.system(size: 11.5)).foregroundStyle(Theme.riskHigh)
            }
            // What was attached, what is being written, and how the turn will
            // run: one block, in that order.
            ComposerBlock {
                AttachmentThumbnails(attachments: $attachments)
                ComposerField(
                    placeholder: dictator.isRecording ? L("Listening…")
                        : (replyRequestId == nil ? L("Message this chat…") : L("Reply…")),
                    text: $draft, focus: $chatFocused, onSubmit: send
                )
                .onChange(of: dictator.transcript) { transcript in
                    if dictator.isRecording { draft = transcript }
                }
                HStack(spacing: 8) {
                    AttachmentMenuButton(attachments: $attachments,
                                         mcpServers: currentSession.mcpServers ?? [],
                                         skills: currentSession.skills ?? [],
                                         selectedMcp: $selectedMcp,
                                         selectedSkill: $selectedSkill)
                    ComposerModelPill(agent: currentSession.agent, model: chatModelBinding,
                                      current: currentSession.model)
                    Spacer(minLength: 4)
                    ListeningMicButton(isRecording: dictator.isRecording,
                                       isStarting: dictator.isStarting,
                                       tint: accent,
                                       action: toggleDictation)
                    let action = ComposerAction.resolve(
                        text: draft, attachments: attachments.count, isFocused: chatFocused
                    )
                    if action.isVisible {
                        ComposerSendButton(
                            action: action, tint: accent,
                            glyphInk: Theme.glyphInk(for: currentSession.agent),
                            blocked: chatSendAvailability?.blocksSending == true,
                            send: send,
                            dismissKeyboard: { chatFocused = false }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        // A picked attachment starts travelling at once, so the message that
        // follows has only to name it.
        .onChange(of: attachments.map(\.id)) { _ in
            model.preuploadAttachments(attachments, room: model.sourceRoom(forSessionId: chatSessionId))
        }
        // Matches the home composer: the safe-area inset is the bottom spacing.
        .padding(.bottom, 4)
        .background(currentSession.agent.lowercased().contains("claude")
                    ? Theme.claudeCanvas.opacity(0.97) : Theme.surface.opacity(0.97))
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
    }

    /// Land on the entry the chat was opened for, once.
    ///
    /// The transcript keeps arriving after the view appears, so the focused
    /// entry may not exist yet on the first pass; the attempt repeats until it
    /// does. Afterwards the chat follows new activity as it always did, or the
    /// user would be dragged back to an old call by every incoming line.
    func settleScroll(_ proxy: ScrollViewProxy) {
        guard let focusEntryId, !focusHonoured else {
            scrollToBottom(proxy)
            return
        }
        guard let entry = entries.first(where: { $0.id == focusEntryId }) else { return }
        focusHonoured = true
        let target = ChatScrollTarget.forEntry(entry)
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(target, anchor: .center)
                highlightedEntryId = focusEntryId
            }
        }
        // The mark is a pointer, not a selection: it fades once it has been seen,
        // leaving the transcript reading as it normally does.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeInOut(duration: 0.4)) { highlightedEntryId = nil }
        }
    }

    func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = entries.last else { return }
        let target = ChatScrollTarget.forEntry(last)
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .bottom) }
        }
    }

    func toggleDictation() {
        if dictator.isRecording { draft = dictator.stop() }
        else { dictator.start() }
    }

    func send() {
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

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

extension ContentView {
    var activeComposeAgent: String {
        selectedComposeSession.map { AgentIdentity.normalize($0.agent) } ?? composeAgent
    }

    /// The model the next turn will use: this chat's own choice when the
    /// composer is aimed at a chat, and the agent's default when a Task is
    /// being started and there is no chat to inherit one from.
    var newTaskModelBinding: Binding<TurnModel?> {
        Binding(
            get: {
                guard let sessionId = selectedComposeSession?.sessionId else {
                    return model.turnOverrides.agentDefaults(for: activeComposeAgent).model
                }
                return model.turnOverrides.chatOverrides(sessionId).model
            },
            set: { picked in
                guard let sessionId = selectedComposeSession?.sessionId else {
                    var current = model.turnOverrides.agentDefaults(for: activeComposeAgent)
                    current.model = picked
                    model.turnOverrides.setAgentDefaults(current, for: activeComposeAgent)
                    return
                }
                var current = model.turnOverrides.chatOverrides(sessionId)
                current.model = picked
                model.turnOverrides.setChatOverrides(current, for: sessionId)
            }
        )
    }

    var composeBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            if selectedComposeSession != nil {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text(composeTargetLabel)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        composeSessionId = nil
                        replyRequestId = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
            }

            if selectedComposeSession != nil, let route = activeComposeRoute {
                Text(TaskRoutePresentation.sessionMetadata(
                    agent: activeComposeAgent,
                    model: selectedComposeSession?.model,
                    project: selectedComposeSession?.projectGroupTitle,
                    route: route
                ))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(route.phase == .live ? Theme.muted : Theme.riskMed)
                .lineLimit(1)
            }
            if let availability = activeSendAvailability {
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

            if dictator.isRecording || dictator.isStarting {
                ListeningStatus(isStarting: dictator.isStarting, language: dictator.detectedLanguage)
            }
            if let error = dictator.errorText {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.riskHigh)
            }

            // The same block a chat is written in, so starting a Task and
            // carrying one on ask for the next turn the same way.
            ComposerBlock {
                AttachmentThumbnails(attachments: $attachments)
                    .onChange(of: attachments.map(\.id)) { _ in
                        model.preuploadAttachments(attachments, room: composeAttachmentRoom)
                    }
                ComposerField(
                    placeholder: dictator.isRecording ? L("Listening…") : composePlaceholder,
                    text: $messageText, focus: $composeFocused, onSubmit: send
                )
                .onChange(of: dictator.transcript) { t in
                    if dictator.isRecording { messageText = t }
                }
                HStack(spacing: 8) {
                    AttachmentMenuButton(attachments: $attachments)
                    ComposerModelPill(agent: activeComposeAgent, model: newTaskModelBinding,
                                      current: selectedComposeSession?.model)
                    Spacer(minLength: 4)
                    ListeningMicButton(isRecording: dictator.isRecording,
                                       isStarting: dictator.isStarting,
                                       tint: Theme.accent(for: activeComposeAgent),
                                       action: toggleDictation)
                    let action = ComposerAction.resolve(
                        text: messageText,
                        attachments: attachments.count,
                        isFocused: composeFocused
                    )
                    if action.isVisible {
                        ComposerSendButton(
                            action: action,
                            tint: Theme.accent(for: activeComposeAgent),
                            glyphInk: Theme.glyphInk(for: activeComposeAgent),
                            blocked: activeSendAvailability?.blocksSending == true,
                            send: send,
                            dismissKeyboard: { composeFocused = false }
                        )
                    }
                }
            }

            if selectedComposeSession == nil {
                DisclosureGroup(isExpanded: $showNewTaskRoute) {
                    TaskComposerRoutePicker(
                        provider: $composeAgent,
                        computerId: $composeRoomId,
                        workspace: $newTaskCwd,
                        computers: taskComposerComputers,
                        workspaces: model.workspaceFolders(for: composeAgent),
                        enabledProviders: model.agentMeshPreferences.enabledProviders
                    )
                    .padding(.top, 8)
                } label: {
                    Label(newTaskRouteLabel, systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        // The home-indicator safe area already sits below this bar; adding a
        // full pad on top of it left an empty band under the field.
        .padding(.bottom, 2)
        .background(Theme.surface.opacity(0.97))
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
    }

    /// computer, or the one chosen for a new Task.
    var composeAttachmentRoom: String? {
        if let composeSessionId { return model.sourceRoom(forSessionId: composeSessionId) }
        return selectedNewTaskConnection?.id ?? model.connectionRegistry.preferredId
    }

    var newTaskRouteLabel: String {
        let provider = AgentIdentity.shortName(composeAgent)
        let computer = selectedNewTaskConnection?.displayName ?? L("No computer")
        return "\(provider) · \(computer)"
    }

    func send() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        guard activeSendAvailability?.blocksSending != true else { return }
        do {
            try AttachmentDraft.validateTotal(attachments)
            attachmentError = nil
        } catch {
            attachmentError = error.localizedDescription
            return
        }
        let payloads = attachments.map(\.payload)
        let wasReply = replyRequestId != nil
        let composeRoom = composeAttachmentRoom
        if !wasReply, selectedComposeSession == nil { savedComposeAgent = activeComposeAgent }
        // MCP ask replies retain their exact request/session scope, but never
        // attach agent/cwd or create a local chat stub.
        model.sendMessage(text,
                          agent: wasReply ? nil : activeComposeAgent,
                          cwd: wasReply ? nil : (composeSessionId == nil && !newTaskCwd.isEmpty ? newTaskCwd : nil),
                          sessionId: composeSessionId,
                          requestId: replyRequestId,
                          attachments: payloads,
                          attachmentRefs: model.attachmentRefs(for: attachments, room: composeRoom),
                          roomId: wasReply || composeSessionId != nil
                            ? nil : selectedNewTaskConnection?.id)
        if let sessionId = model.sessionToOpen {
            if openedSession?.id != sessionId {
                openedSession = OpenSession(id: sessionId)
            }
        } else if let session = selectedComposeSession,
                  openedSession?.id != session.sessionId {
            openedSession = OpenSession(id: session.sessionId)
        }
        replyRequestId = nil
        if wasReply { composeSessionId = nil }
        messageText = ""
        attachments = []
        attachmentError = nil
        composeFocused = false
        showNewTask = false
    }

    var selectedComposeSession: SessionInfo? {
        guard let composeSessionId else { return nil }
        return model.sessions.first(where: { $0.sessionId == composeSessionId })
    }

    var composeTargetLabel: String {
        selectedComposeSession?.displayTitle
            ?? AgentIdentity.newTaskLabel()
    }

    var selectedNewTaskConnection: LinkedComputer? {
        if let composeRoomId,
           let selected = model.connectionRegistry.connections.first(where: { $0.id == composeRoomId }) {
            return selected
        }
        return model.connectionRegistry.preferred
    }

    var activeComposeRoute: ChatComputerRoute? {
        if let sessionId = selectedComposeSession?.sessionId {
            return model.chatComputerRoute(forSessionId: sessionId)
        }
        return model.chatComputerRoute(forRoomId: selectedNewTaskConnection?.id)
    }

    var activeSendAvailability: TaskSendAvailability? {
        // Nothing is sent in the demo, so nothing is missing for sending.
        if model.demoMode { return nil }
        return TaskRoutePresentation.sendAvailability(
            agent: activeComposeAgent,
            route: activeComposeRoute
        )
    }

    var taskComposerComputers: [TaskComposerComputerOption] {
        model.connectionRegistry.connections.map { connection in
            TaskComposerComputerOption(
                id: connection.id,
                name: TaskComposerRoutePresentation.computerName(
                    pairingLabel: connection.displayName,
                    publishedMachineName: connection.lastMachineName
                ),
                phase: model.snapshotForConnection(connection).phase
            )
        }
    }

    var composePlaceholder: String {
        selectedComposeSession == nil ? L("Describe a new task…") : L("Message this task…")
    }

    /// Hold-free toggle: tap to dictate, tap again to stop; words stream into
    /// the field so you can edit before sending.
    func toggleDictation() {
        if dictator.isRecording {
            messageText = dictator.stop()
        } else {
            dictator.start()
        }
    }
}

/// A text editor drawn on the card, not on its own white slab.
struct ClearTextEditorBackground: ViewModifier {
    init() {
        // Before iOS 16 the editor's UIKit view paints its own background.
        UITextView.appearance().backgroundColor = .clear
    }

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

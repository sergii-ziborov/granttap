import SwiftUI
import PhotosUI

/// The sheet that starts a Task: which computer and agent it goes to, what it
/// is asked to do, and what travels with the first message.
extension ContentView {
    var newTaskSheet: some View {
        CompatNavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedComposeSession == nil ? L("Task") : L("Reply"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                Spacer()
                if selectedComposeSession == nil {
                    newTaskComposer
                } else {
                    composeBar
                }
            }
            .background(Theme.bg)
            .navigationTitle(selectedComposeSession == nil ? L("New Task") : composeTargetLabel)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Cancel")) { showNewTask = false }
                }
            }
        }
    }

    /// A new task is written, not typed into a slot. The card gives the text
    /// room to be several lines, keeps the attachments in view above it, and
    /// puts the way to send where the thumb already is.
    var newTaskComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                AttachmentThumbnails(attachments: $attachments)
                .onChange(of: attachments.map(\.id)) { _ in
                    model.preuploadAttachments(attachments, room: composeAttachmentRoom)
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
                ZStack(alignment: .topLeading) {
                    if messageText.isEmpty {
                        Text(dictator.isRecording ? L("Listening…") : composePlaceholder)
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $messageText)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: 120, maxHeight: 260)
                        .focused($composeFocused)
                        .modifier(ClearTextEditorBackground())
                        .onChange(of: dictator.transcript) { t in
                            if dictator.isRecording { messageText = t }
                        }
                        .accessibilityIdentifier("compose.task-text")
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
                        text: messageText, attachments: attachments.count, isFocused: composeFocused
                    )
                    ComposerSendButton(
                        action: action,
                        tint: Theme.accent(for: activeComposeAgent),
                        glyphInk: Theme.glyphInk(for: activeComposeAgent),
                        blocked: !action.isVisible || activeSendAvailability?.blocksSending == true,
                        send: send,
                        dismissKeyboard: { composeFocused = false }
                    )
                    .opacity(action.isVisible ? 1 : 0.35)
                    .accessibilityIdentifier("compose.task-send")
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.line, lineWidth: 1))

            if let availability = activeSendAvailability {
                Text(availability.message)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(availability.blocksSending ? Theme.riskHigh : Theme.riskMed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup(isExpanded: $showNewTaskRoute) {
                TaskComposerRoutePicker(
                    provider: $composeAgent,
                    computerId: $composeRoomId,
                    workspace: $newTaskCwd,
                    computers: taskComposerComputers,
                    workspaces: model.workspaceFolders(for: composeAgent),
                    enabledProviders: model.agentMeshPreferences.enabledProviders,
                    pinnedEndpointId: model.pinnedEndpointId(forWorkspace: newTaskCwd)
                )
                .padding(.top, 8)
            } label: {
                Label(newTaskRouteLabel, systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.bg)
    }

    /// Where a picked attachment goes ahead of the message: the chat's own
}

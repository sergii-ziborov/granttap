import SwiftUI
import PhotosUI

/// The sheet that starts a Task: which computer and agent it goes to, what it
/// is asked to do, and what travels with the first message.
extension ContentView {
    private var showComposerAvailabilityBelow: Bool {
        #if targetEnvironment(macCatalyst)
        return !model.demoMode && !(model.pairing == nil && macLocalMCP.status != nil)
        #else
        return true
        #endif
    }

    var newTaskSheet: some View {
        #if targetEnvironment(macCatalyst)
        macNewTaskSheet
        #else
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
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private var macNewTaskSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image("BrandMark").resizable().scaledToFit()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Text(L("New Task")).font(.system(size: 24, weight: .bold))
                Spacer()
                Button(L("Cancel")) { showNewTask = false }
                    .buttonStyle(.bordered)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Agent · Computer · Workspace"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                TaskComposerRoutePicker(
                    provider: $composeAgent, computerId: $composeRoomId,
                    workspace: $newTaskCwd, computers: taskComposerComputers,
                    workspaces: model.workspaceFolders(for: composeAgent),
                    enabledProviders: model.agentMeshPreferences.enabledProviders
                )
            }
            if model.demoMode {
                Label(L("Demo Mac is sample data. Connect this app to send a real Task."),
                      systemImage: "info.circle")
                    .foregroundStyle(Theme.muted)
            } else if model.pairing == nil && macLocalMCP.status != nil {
                Text(L("Local MCP is available, but this app cannot send to the Task yet."))
                    .foregroundStyle(Theme.riskMed)
            }
            newTaskComposer
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 780, height: 560)
        .background(Theme.bg.ignoresSafeArea())
    }
    #endif

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
                                      current: selectedComposeSession?.model,
                                      catalog: model.turnModelCatalog(agent: activeComposeAgent,
                                          session: selectedComposeSession, roomId: selectedNewTaskConnection?.id),
                                      fallback: selectedComposeSession == nil ? nil
                                          : model.turnOverrides.agentDefaults(for: activeComposeAgent).model?.id,
                                      hasConversation: selectedComposeSession != nil)
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

            if showComposerAvailabilityBelow, let availability = activeSendAvailability {
                Text(availability.message)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(availability.blocksSending ? Theme.riskHigh : Theme.riskMed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #if !targetEnvironment(macCatalyst)
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
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.bg)
    }

    /// Where a picked attachment goes ahead of the message: the chat's own
}

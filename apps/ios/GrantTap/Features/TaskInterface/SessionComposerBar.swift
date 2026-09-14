import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct SessionComposerBar: View {
    let sessionId: String
    let agent: String
    let mcpServers: [McpServerInfo]
    let skills: [SkillInfo]
    let accent: Color
    @EnvironmentObject private var environmentModel: AppModel
    var modelOverride: AppModel?
    var model: AppModel { modelOverride ?? environmentModel }
    @State var draft = ""
    @State var attachments: [AttachmentDraft] = []
    @State var attachmentError: String?
    @State var selectedMcp: String?
    @State var selectedSkill: String?
    @StateObject var dictator: Dictator

    init(
        sessionId: String, agent: String, mcpServers: [McpServerInfo],
        skills: [SkillInfo], accent: Color, modelOverride: AppModel? = nil,
        initialDraft: String = "", initialAttachments: [AttachmentDraft] = [],
        initialSelectedMcp: String? = nil, initialSelectedSkill: String? = nil,
        initialAttachmentError: String? = nil, dictator: Dictator? = nil
    ) {
        self.sessionId = sessionId
        self.agent = agent
        self.mcpServers = mcpServers
        self.skills = skills
        self.accent = accent
        self.modelOverride = modelOverride
        _draft = State(initialValue: initialDraft)
        _attachments = State(initialValue: initialAttachments)
        _selectedMcp = State(initialValue: initialSelectedMcp)
        _selectedSkill = State(initialValue: initialSelectedSkill)
        _attachmentError = State(initialValue: initialAttachmentError)
        _dictator = StateObject(wrappedValue: dictator ?? Dictator())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AttachmentStrip(attachments: $attachments)
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
            HStack(spacing: 10) {
                AttachmentMenuButton(attachments: $attachments,
                                     mcpServers: mcpServers,
                                     skills: skills,
                                     selectedMcp: $selectedMcp,
                                     selectedSkill: $selectedSkill)
                ListeningMicButton(isRecording: dictator.isRecording,
                                   isStarting: dictator.isStarting,
                                   tint: accent,
                                   action: toggleDictation)
                HStack {
                    TextField(dictator.isRecording ? L("Listening…") : L("Message this chat…"),
                              text: $draft)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink)
                        .submitLabel(.send)
                        .onSubmit(send)
                        .onChange(of: dictator.transcript) { transcript in
                            if dictator.isRecording { draft = transcript }
                        }
                    if !draft.trimmingCharacters(in: .whitespaces).isEmpty || !attachments.isEmpty {
                        Button(action: send) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.glyphInk(for: agent))
                                .frame(width: 28, height: 28)
                                .background(accent, in: Circle())
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Theme.raised, in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(agent.lowercased().contains("claude")
                    ? Theme.claudeCanvas.opacity(0.97) : Theme.surface.opacity(0.97))
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        do {
            try AttachmentDraft.validateTotal(attachments)
            attachmentError = nil
        } catch {
            attachmentError = error.localizedDescription
            return
        }
        model.sendMessage(text, agent: agent, sessionId: sessionId,
                          attachments: attachments.map(\.payload), preferredMcp: selectedMcp,
                          skill: selectedSkill)
        draft = ""
        attachments = []
        attachmentError = nil
        selectedMcp = nil
        selectedSkill = nil
    }

    private func toggleDictation() {
        if dictator.isRecording { draft = dictator.stop() }
        else { dictator.start() }
    }
}

// MARK: - full task chat

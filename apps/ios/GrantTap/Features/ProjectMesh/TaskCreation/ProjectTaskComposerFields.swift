import SwiftUI

extension ProjectNewTaskView {
    var taskEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Task")).font(.subheadline.weight(.semibold))
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft.text)
                    .font(.system(size: 16))
                    .focused($descriptionFocused)
                    .accessibilityIdentifier("project.task.description")
                if draft.text.isEmpty {
                    Text(L("Describe what you want the agent to do…"))
                        .foregroundStyle(Theme.muted).padding(.horizontal, 5).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 160)
            .padding(10)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            HStack {
                AttachmentMenuButton(attachments: $draft.attachments)
                Text(L("Add images or files")).font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                if draft.text.utf16.count > 7_500 {
                    Text("\(draft.text.utf16.count)/8000").font(.caption.monospacedDigit())
                        .foregroundStyle(draft.text.utf16.count > 8_000 ? Theme.riskHigh : Theme.muted)
                }
            }
            AttachmentThumbnails(attachments: $draft.attachments)
        }
        .disabled(draft.sending)
    }

    var routeFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Run on")).font(.subheadline.weight(.semibold))
            VStack(spacing: 0) {
                routeRow(L("Agent"), symbol: "sparkles") {
                    Picker(L("Agent"), selection: $draft.provider) {
                        ForEach(context.providers, id: \.self) { Text(AgentIdentity.displayName($0)).tag($0) }
                    }.accessibilityIdentifier("project.task.provider")
                }
                Divider()
                routeRow(L("Computer"), symbol: "desktopcomputer") {
                    Picker(L("Computer"), selection: $draft.endpointId) {
                        ForEach(context.endpointIds, id: \.self) { Text(computerName($0)).tag($0) }
                    }.accessibilityIdentifier("project.task.computer")
                }
                Divider()
                routeRow(L("Workspace"), symbol: "folder") {
                    Picker(L("Workspace"), selection: $draft.bindingId) {
                        ForEach(context.bindings(on: draft.endpointId)) { binding in
                            Text(ProjectTaskCreationContext.workspaceName(binding)).tag(binding.bindingId)
                        }
                    }.accessibilityIdentifier("project.task.workspace")
                }
                Divider()
                routeRow(L("Model"), symbol: "cpu") {
                    ComposerModelPill(agent: draft.provider, model: $draft.model, effort: $draft.effort, catalog: catalog)
                }
            }
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            if let path = selectedBinding?.localPathHint {
                Text(path).font(.caption).foregroundStyle(Theme.muted).lineLimit(2).textSelection(.enabled)
                    .accessibilityIdentifier("project.task.path")
            }
        }
        .disabled(draft.sending)
    }

    var effortControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            ComposerEffortPicker(agent: draft.provider, selection: $draft.effort, fallback: nil,
                choices: catalog.efforts(for: draft.model?.id, agent: draft.provider))
        }
        .padding(14)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
        .disabled(draft.sending)
    }

    var taskFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let problem = draft.error ?? draft.problem(context) {
                Text(problem).font(.caption).foregroundStyle(Theme.riskHigh)
                    .accessibilityIdentifier("project.task.error")
            } else if model.demoMode {
                Text(L("Demo preview")).font(.caption).foregroundStyle(Theme.muted)
            }
            Button(action: createTask) {
                HStack(spacing: 8) {
                    if draft.sending { ProgressView() }
                    Text(L(draft.sending ? "Creating Task…" : "Create Task"))
                        .font(.body.weight(.semibold))
                }.frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!draft.canCreate(context) || model.demoMode)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("project.task.create")
        }
        .padding(16)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func routeRow<Control: View>(_ title: String, symbol: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(Theme.muted)
            Spacer(minLength: 6)
            control().labelsHidden().pickerStyle(.menu).tint(Theme.ink)
        }.padding(.horizontal, 12).frame(minHeight: 48)
    }

    private func computerName(_ endpoint: String) -> String {
        #if targetEnvironment(macCatalyst)
        if endpoint == context.localEndpointId { return model.localMCPReader?.status?.computer ?? L("This Mac") }
        #endif
        if let room = context.rooms[endpoint], let route = model.chatComputerRoute(forRoomId: room) { return route.computerName }
        return endpoint
    }
}

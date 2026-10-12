import SwiftUI

struct ApprovalDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let request: ApprovalRequest
    @State private var showingParameters = false

    var body: some View {
        CompatNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    actionSummary
                    if request.kind == "question" {
                        ClaudeQuestionReplyView(request: request)
                    } else {
                        ApprovalChatControls(request: request)
                    }
                }
                .padding(16).frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(Theme.bg)
            .navigationTitle(request.kind == "question" ? L("Questions") : L("Action details"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
            .onChange(of: model.sessionToOpen) { if $0 != nil { dismiss() } }
        }
    }

    private var actionSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AgentGlyph(agent: request.agent, size: 36)
                Text(request.agent.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8).foregroundStyle(Theme.accent(for: request.agent))
                Spacer(minLength: 8)
                Pill(text: Theme.riskLabel(request.risk), color: Theme.risk(request.risk))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(request.title).font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("approval.detail.title")
                Label(request.tool, systemImage: "wrench.and.screwdriver")
                    .font(Theme.mono(11)).foregroundStyle(Theme.muted)
                    .textSelection(.enabled).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let command = request.command, !command.isEmpty {
                commandBlock(command)
            }
            if let cwd = request.cwd, !cwd.isEmpty {
                Label {
                    Text(cwd).textSelection(.enabled)
                } icon: {
                    Image(systemName: "folder")
                }
                .font(Theme.mono(11)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let details = request.details, !details.isEmpty {
                Divider().overlay(Theme.line)
                DisclosureGroup(isExpanded: $showingParameters) {
                    Text(readableParameters(details))
                        .font(Theme.mono(12)).foregroundStyle(Theme.ink).lineSpacing(3)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                        .accessibilityIdentifier("approval.detail.parameters")
                } label: {
                    Label(L("Parameters"), systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                }
                .tint(Theme.muted)
            }
        }
        .card()
    }

    private func commandBlock(_ command: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.top, 2)
            Text(command).font(Theme.mono(13)).foregroundStyle(Theme.ink).lineSpacing(3)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("approval.detail.command")
        }
        .padding(12)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func readableParameters(_ details: String) -> String {
        guard let data = details.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: object,
                                                         options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: formatted, encoding: .utf8) else { return details }
        return text
    }
}

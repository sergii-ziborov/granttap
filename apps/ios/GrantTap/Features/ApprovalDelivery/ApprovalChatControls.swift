import SwiftUI

/// A chat rule is shown as applied only after its owning computer confirms it.
struct ApprovalChatControls: View {
    @EnvironmentObject private var model: AppModel
    let request: ApprovalRequest
    @State private var automationEnabled = false
    @State private var selectedLevel = AutoAcceptLevel.exceptPush

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let id = model.approvalChatId(request) {
                Button { model.sessionToOpen = id } label: {
                    HStack(spacing: 10) {
                        Label(L("Open chat"), systemImage: "bubble.left.and.bubble.right")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    .padding(14).frame(minHeight: 46)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                }
                .pointerButtonStyle(cornerRadius: Theme.radiusSmall)
                .accessibilityIdentifier("approval.open-chat.\(request.requestId)")
            }
            if let nativeId = request.sessionId {
                automation(nativeId)
            } else {
                Label(L("This request has no chat identity. Automation is unavailable."),
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private func automation(_ nativeId: String) -> some View {
        let room = model.requestSourceRoom[request.requestId]
        let available = room.map { model.sessionSourceRooms[nativeId] == [$0]
            && model.roomRuntime[$0]?.socketUp == true } ?? false
        let waiting = model.automationPending[nativeId] != nil
        let confirmed = model.autoAcceptLevel(for: nativeId)
        let desired = automationEnabled ? selectedLevel.rawValue : AutoAcceptLevel.ask.rawValue
        let hasChanges = desired != confirmed
        return VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $automationEnabled) {
                Label(L("Auto allow in this chat"), systemImage: "bolt.shield")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            .tint(Theme.ok)
            .disabled(!available || waiting || model.demoMode)
            .accessibilityIdentifier("approval.auto-safe.\(request.requestId)")

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(L("Mode")).font(.subheadline).foregroundStyle(Theme.muted)
                    Spacer(minLength: 8)
                    Picker(L("Automation mode"), selection: $selectedLevel) {
                        ForEach(AutoAcceptLevel.allCases.filter { $0 != .ask }) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.menu).tint(Theme.ink)
                    .disabled(!automationEnabled || !available || waiting || model.demoMode)
                }
                Text(selectedLevel.blurb).font(.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))

            automationStatus(nativeId, available: available, waiting: waiting,
                             confirmed: confirmed, hasChanges: hasChanges)

            Button {
                apply(nativeId, level: desired)
            } label: {
                Label(waiting ? L("Applying…") : L("Apply to this chat"), systemImage: "checkmark")
            }
                .buttonStyle(FilledButton(tint: Theme.accent(for: request.agent),
                                          textColor: Theme.glyphInk(for: request.agent)))
                .disabled(!available || waiting || model.demoMode
                          || (!hasChanges && model.automationErrors[nativeId] == nil))
                .accessibilityIdentifier("approval.apply-automation.\(request.requestId)")

            Label(L("The current request still needs your decision. Global action bans always apply."),
                  systemImage: "lock.shield")
                .font(.caption2).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .onAppear {
            automationEnabled = confirmed != "ask"
            if let level = AutoAcceptLevel(rawValue: confirmed), level != .ask {
                selectedLevel = level
            }
        }
    }

    @ViewBuilder
    private func automationStatus(_ nativeId: String, available: Bool, waiting: Bool,
                                  confirmed: String, hasChanges: Bool) -> some View {
        if waiting {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(L("Waiting for the computer to confirm…"))
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
            }
        } else if let error = model.automationErrors[nativeId] {
            statusMessage(L("Not applied"), detail: error, symbol: "exclamationmark.circle",
                          color: Theme.riskHigh)
        } else if model.demoMode {
            statusMessage(L("Demo preview"), detail: nil, symbol: "info.circle", color: Theme.muted)
        } else if !available {
            statusMessage(L("Reconnect this chat's computer to change its automation."),
                          detail: nil, symbol: "wifi.slash", color: Theme.riskMed)
        } else if !hasChanges {
            statusMessage(confirmed == "ask" ? L("Ask always") : L("Applied on computer"),
                          detail: nil, symbol: confirmed == "ask" ? "hand.raised" : "checkmark.shield",
                          color: confirmed == "ask" ? Theme.muted : Theme.ok)
        }
    }

    private func statusMessage(_ title: String, detail: String?, symbol: String,
                               color: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 14)).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.semibold))
                if let detail { Text(detail).font(.caption).foregroundStyle(Theme.muted) }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color).padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func apply(_ id: String, level: String) {
        model.setSessionAutoAccept(id, level, authorizeProjectAsk: true,
                                   expectedPolicyRevision: request.policyRevision,
                                   approvalRequestId: request.requestId)
    }
}

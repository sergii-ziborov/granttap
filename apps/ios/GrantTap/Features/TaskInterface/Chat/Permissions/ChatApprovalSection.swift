import SwiftUI

/// Shared by the composer shortcut and Task controls, with one underlying rule.
struct ChatApprovalSection: View {
    let sessionId: String
    let session: SessionInfo
    @ObservedObject var model: AppModel

    private var preferences: ChatApprovalPreferences {
        ChatApprovalPreferences(sessionId: sessionId, session: session, model: model)
    }
    private var waiting: Bool { model.automationPending[sessionId] != nil }
    private var available: Bool { preferences.available }

    var body: some View {
        Section {
            ForEach(PersonalApprovalMode.allCases.filter { $0 != .custom || preferences.mode == .custom }) { mode in
                Button { preferences.apply(mode) } label: {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 22)).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.label).font(.body.weight(.medium))
                            Text(mode.detail).font(.caption).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if preferences.mode == mode {
                            Image(systemName: "checkmark").font(.body.weight(.semibold))
                        }
                    }
                    .foregroundStyle(mode == .full ? Theme.riskMed : Theme.ink)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .pointerButtonStyle()
                .disabled(waiting || !available || mode == .custom)
                .accessibilityIdentifier("chat.approval.select.\(mode.rawValue)")
                .accessibilityValue(preferences.mode == mode ? L("Selected") : "")
                .accessibilityAddTraits(preferences.mode == mode ? .isSelected : [])
            }
        } header: {
            Text(L("Approval Mode"))
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if waiting {
                    HStack { ProgressView(); Text(L("Waiting for the computer to confirm…")) }
                        .accessibilityIdentifier("chat.approval.pending")
                } else if let error = model.automationErrors[sessionId] {
                    Text(error).foregroundStyle(Theme.riskHigh)
                } else if model.demoMode {
                    Text(L("Demo preview"))
                } else if !available {
                    Text(L("Reconnect this chat's computer to change its automation."))
                }
                if model.autoAcceptPaused {
                    Text(L("Automation is paused globally. Resume it in Settings."))
                }
                if !model.gatingEnabled {
                    Text(L("GrantTap approvals are paused. The provider's own rules still apply."))
                }
                Text(L("These rules apply only to this chat. The provider's own permissions and Mesh blocks still apply."))
            }
            .font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

struct ChatApprovalAccessSection: View {
    let sessionId: String
    let session: SessionInfo
    @ObservedObject var model: AppModel

    var body: some View {
        if AgentIdentity.normalize(session.agent) == "codex" {
            Section {
                Picker(L("Codex access"), selection: Binding(
                    get: { model.knownSession(for: sessionId, preferredAgent: session.agent)?.accessLevel
                        ?? session.accessLevel ?? "workspace" },
                    set: { model.setSessionAccess(sessionId, $0) })) {
                    Text(L("Read only")).tag("read-only")
                    Text(L("Workspace")).tag("workspace")
                    Text(L("Full access")).tag("full")
                }
                .accessibilityIdentifier("chat.approval.access")
                .disabled(!ChatApprovalPreferences(sessionId: sessionId, session: session, model: model).available)
            } header: {
                Text(L("Access"))
            } footer: {
                Text(L("Applies to the next turn sent from GrantTap."))
            }
        }
    }
}

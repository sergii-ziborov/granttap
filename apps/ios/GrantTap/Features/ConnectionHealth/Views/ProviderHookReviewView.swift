import SwiftUI

/// Review the native Codex definition on one computer before trusting it.
struct ProviderHookReviewView: View {
    @EnvironmentObject private var model: AppModel
    let room: String
    let endpointId: String?
    let computer: String
    var localHooks: [ProviderHookInfo]? = nil
    @State private var confirming: ProviderHookInfo?

    private var hooks: [ProviderHookInfo] {
        #if targetEnvironment(macCatalyst)
        if room == "local-mac" {
            return localHooks ?? []
        }
        #endif
        return model.agentIntegrationsByRoom[room]?.first { $0.agent == "codex" }?.hooks ?? []
    }

    var body: some View {
        List {
            Section {
                Label(computer, systemImage: "desktopcomputer")
                Text(L("Codex skips new or changed hooks until you review and trust their current definition."))
                    .foregroundStyle(Theme.muted)
            }
            if hooks.isEmpty {
                Section {
                    Text(L("Hook status is unavailable"))
                    Text(L("Update GrantTap MCP on this computer, or review GrantTap hooks in Codex Settings → Hooks."))
                        .foregroundStyle(Theme.muted)
                }
            }
            ForEach(hooks) { hook in
                Section {
                    Text(hook.title).foregroundStyle(hook.isActive ? Theme.ok : Theme.riskMed)
                    Text(hook.purpose).foregroundStyle(Theme.muted)
                    if let command = hook.command {
                        Text(command).font(Theme.mono(12)).textSelection(.enabled)
                    }
                    if let hash = hook.currentHash {
                        Text(L("Definition hash") + ": " + hash)
                            .font(Theme.mono(11)).foregroundStyle(Theme.muted).textSelection(.enabled)
                    }
                    reviewResult(hook)
                    if !hook.isActive && hook.canReview {
                        Button(L("Trust and enable this hook")) { confirming = hook }
                            .disabled(endpointId == nil || isPending(hook))
                            .accessibilityIdentifier("provider-hook.trust.\(hook.event)")
                    }
                } header: { Text(hook.event) }
            }
        }
        .pageNavigationTitle(L("Codex hooks")) {
            Button(L("Refresh")) { refresh() }
                .accessibilityIdentifier("provider-hook.refresh")
        }
        .alert(L("Trust and enable this GrantTap hook?"), isPresented: Binding(
            get: { confirming != nil }, set: { if !$0 { confirming = nil } }
        )) {
            Button(L("Trust and enable")) {
                if let hook = confirming, let endpointId {
                    _ = model.reviewProviderHook(hook, room: room, endpointId: endpointId)
                }
                confirming = nil
            }
            Button(L("Cancel"), role: .cancel) { confirming = nil }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationMessage: String {
        let heading = "\(confirming?.event ?? "") · \(computer)"
        let scope = L("This trust applies to all Codex projects on this computer.")
        let command = L("Codex runs this command outside its sandbox. This approves the displayed definition for Codex on this computer.")
        return [heading, command, scope].joined(separator: "\n\n")
    }

    private func refresh() {
        #if targetEnvironment(macCatalyst)
        if room == "local-mac", let reader = model.localMCPReader {
            Task { await reader.refresh() }
            return
        }
        #endif
        model.relaysByRoom[room]?.requestSessionsRefresh()
    }

    private func isPending(_ hook: ProviderHookInfo) -> Bool {
        if case .pending = model.providerHookReviews[AppModel.hookReviewKey(room: room, event: hook.event)] {
            return true
        }
        return false
    }

    @ViewBuilder
    private func reviewResult(_ hook: ProviderHookInfo) -> some View {
        switch model.providerHookReviews[AppModel.hookReviewKey(room: room, event: hook.event)] {
        case .pending: ProgressView(L("Applying…"))
        case .finished(let result): Text(L(result.message)).foregroundStyle(result.ok ? Theme.ok : Theme.riskMed)
        case .unavailable: Text(L("Hook approval was not confirmed. Refresh and try again."))
        case nil: EmptyView()
        }
    }
}

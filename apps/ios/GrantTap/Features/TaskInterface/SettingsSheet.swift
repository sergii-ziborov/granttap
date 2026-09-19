import SwiftUI

enum DefaultApprovalMode: String, CaseIterable, Identifiable {
    case risky
    case every
    case defaults

    var id: String { rawValue }
    var label: String {
        switch self {
        case .risky: return L("Ask for risky actions")
        case .every: return L("Ask for every action")
        case .defaults: return L("Use agent defaults")
        }
    }
}

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environmentModel: AppModel
    var modelOverride: AppModel?
    var model: AppModel { modelOverride ?? environmentModel }
    @AppStorage(AppLocale.storageKey) private var language = "en"
    @State private var showForgetConfirmation = false
    @State private var showPairing = false

    private let links = GrantTapLinks.all

    init(modelOverride: AppModel? = nil) {
        self.modelOverride = modelOverride
    }

    var body: some View {
        CompatNavigationStack {
            List {
                SettingsConnectionSection(
                    onPair: { showPairing = true },
                    onForgetAll: { showForgetConfirmation = true }
                )

                AgentsMeshSettingsSection(model: model)

                SettingsSecuritySection()

                Section(L("Subscription")) {
                    NavigationLink {
                        SubscriptionView()
                    } label: {
                        Label(L("Manage subscription"), systemImage: "creditcard")
                    }
                }

                Section(L("Help & About")) {
                    // How the whole thing works, in the app rather than only
                    // on the website.
                    NavigationLink {
                        LearnView()
                    } label: {
                        Label(L("Learn"), systemImage: "book")
                    }
                    .accessibilityIdentifier("settings.open-learn")
                    Picker(L("Language"), selection: $language) {
                        Text(L("English")).tag("en")
                        Text(L("Русский")).tag("ru")
                    }
                    NavigationLink {
                        AboutGrantTapView()
                    } label: {
                        Label(L("About GrantTap"), systemImage: "info.circle")
                    }
                    ForEach(Array(links.enumerated()), id: \.offset) { _, item in
                        if let url = URL(string: item.1) {
                            Link(destination: url) {
                                HStack {
                                    Text(L(item.0))
                                    Spacer()
                                    Image(systemName: "arrow.up.right").foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                    CompatLabeledContent(L("Version"), value: AppVersion.display)
                }

                Section {
                    NavigationLink {
                        TroubleshootingView().environmentObject(model)
                    } label: {
                        Label(L("Troubleshooting"), systemImage: "wrench.and.screwdriver")
                    }
                }

                if model.demoMode {
                    Section {
                        Button(L("Exit Demo"), role: .destructive) {
                            model.stopDemo()
                            dismiss()
                        }
                    } footer: {
                        Text(L("Demo uses sample data and never executes a command."))
                    }
                }
            }
            .navigationTitle(L("Settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showPairing) { PairingSheet().environmentObject(model) }
            .confirmationDialog(L("Unlink all computers?"),
                                isPresented: $showForgetConfirmation,
                                titleVisibility: .visible) {
                Button(L("Unlink all"), role: .destructive) { model.forgetPairing() }
                Button(L("Cancel"), role: .cancel) {}
            } message: {
                Text(L("This removes every linked computer and local session state from this iPhone."))
            }
        }
    }

    var approvalBinding: Binding<DefaultApprovalMode> {
        Binding(get: {
            guard model.gatingEnabled else { return .defaults }
            return model.autoAcceptPaused || model.autoAcceptDefault == "ask" ? .every : .risky
        }, set: { mode in
            model.setAutoAcceptPaused(false)
            switch mode {
            case .defaults:
                model.setGating(false)
            case .every:
                model.setGating(true)
                model.setAutoAcceptDefault("ask")
            case .risky:
                model.setGating(true)
                model.setAutoAcceptDefault("except_push")
            }
        })
    }
}

struct TroubleshootingView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var push: PushRegistrationManager
    @State private var confirmClearCache = false
    @State private var showPairing = false

    init(push: PushRegistrationManager? = nil) {
        self.push = push ?? .shared
    }

    var body: some View {
        List {
            Section(L("Connection")) {
                HStack {
                    Text(L("Background delivery"))
                    Spacer()
                    PushStatusLabel(state: push.state)
                }
                Button(L("Register background delivery again")) { push.registerAgain() }
                    .disabled(model.pairing == nil)
                Button(L("Scan QR or enter pairing token")) { showPairing = true }
            }

            Section(L("Provider readiness")) {
                readiness("Claude Code", status: L("Run granttap setup"))
                readiness("Codex", status: L("Trust hooks in /hooks"))
                readiness("Cursor", status: L("Beta · granttap cursor repair"))
            }

            Section(L("Diagnostics")) {
                CompatLabeledContent(L("Connection"), value: model.connectionSnapshot.statusTitle)
                CompatLabeledContent(L("Linked computers"),
                                     value: "\(model.connectionRegistry.connections.count)")
                NavigationLink {
                    BugReportView(model: model)
                } label: {
                    Label(L("Report a problem"), systemImage: "ladybug")
                }
                Button(L("Clear local chat cache"), role: .destructive) {
                    confirmClearCache = true
                }
            }
        }
        .navigationTitle(L("Troubleshooting"))
        .sheet(isPresented: $showPairing) { PairingSheet().environmentObject(model) }
        .confirmationDialog(L("Clear local chat cache?"),
                            isPresented: $confirmClearCache,
                            titleVisibility: .visible) {
            Button(L("Clear cache"), role: .destructive) { model.clearLocalSessionCache() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Mac tasks are unchanged and will reappear on the next update."))
        }
    }

    func readiness(_ provider: String, status: String) -> some View {
        HStack {
            Text(provider)
            Spacer()
            Text(status).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

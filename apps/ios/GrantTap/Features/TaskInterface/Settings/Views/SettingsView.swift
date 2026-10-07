import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environmentModel: AppModel
    var modelOverride: AppModel?
    var localComputer: String?
    var localPaired: Bool?
    var localRelayStatus: String?
    var localPhoneReachability: String?
    var onExitDemo: () -> Void
    var model: AppModel { modelOverride ?? environmentModel }
    @AppStorage(AppLocale.storageKey) private var language = "en"

    init(modelOverride: AppModel? = nil, localComputer: String? = nil,
         localPaired: Bool? = nil, localRelayStatus: String? = nil,
         localPhoneReachability: String? = nil,
         onExitDemo: @escaping () -> Void = {}) {
        self.modelOverride = modelOverride
        self.localComputer = localComputer
        self.localPaired = localPaired
        self.localRelayStatus = localRelayStatus
        self.localPhoneReachability = localPhoneReachability
        self.onExitDemo = onExitDemo
    }

    var body: some View {
        List {
            AgentsMeshSettingsSection(model: model)

            Section(L("Company")) {
                NavigationLink {
                    CompanyAccountsView(model: model)
                } label: {
                    Label(L("Company accounts & repositories"), systemImage: "person.2.badge.key")
                }
                .accessibilityIdentifier("settings.company-accounts")
            }

            SettingsSecuritySection()

            Section(L("Subscription")) {
                #if targetEnvironment(macCatalyst)
                NavigationLink {
                    DesktopLicenseView()
                } label: {
                    Label(L("Mac license"), systemImage: "checkmark.seal")
                }
                .accessibilityIdentifier("settings.mac-license")
                #endif
                NavigationLink {
                    SubscriptionView()
                } label: {
                    Label(L("Manage subscription"), systemImage: "creditcard")
                }
            }

            helpSection

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
                        onExitDemo()
                    }
                } footer: {
                    Text(L("Demo uses sample data and never executes a command."))
                }
            }
        }
        .pageNavigationTitle(L("Settings"), showsBack: false)
        .accessibilityIdentifier("settings.page")
        #if targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var helpSection: some View {
    Section(L("Help & About")) {
        // How the whole thing works, in the app rather than only
        // on the website.
        NavigationLink {
            LearnView()
        } label: {
            Label(L("Learn"), systemImage: "book")
        }
        .accessibilityIdentifier("settings.open-learn")
        NavigationLink(L("GrantTap Help")) { ProductInformationView(information: .help) }
            .accessibilityIdentifier("settings.open-help")
        Picker(L("Language"), selection: $language) {
            Text(L("English")).tag("en")
            Text(L("Русский")).tag("ru")
        }
        NavigationLink {
            AboutGrantTapView()
        } label: {
            Label(L("About GrantTap"), systemImage: "info.circle")
        }
        ProductInformationLinks(includesHelp: false)
        CompatLabeledContent(L("Version"), value: AppVersion.display)
    }
    }
}

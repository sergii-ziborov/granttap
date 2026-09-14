import SwiftUI
import WatchKit

struct WatchSettingsView: View {
    @AppStorage(AppLocale.storageKey) private var language = "en"

    var body: some View {
        List {
            Section(L("Language")) {
                Picker(L("Language"), selection: $language) {
                    Text(L("English")).tag("en")
                    Text(L("Russian")).tag("ru")
                }
            }
            Section(L("About")) {
                NavigationLink {
                    WatchAboutView()
                } label: {
                    Label(L("About GrantTap"), systemImage: "info.circle")
                }
                LabeledContent("Version", value: AppVersion.display)
            }
        }
        .navigationTitle(L("Settings"))
    }
}

struct WatchAboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: pt(6)) {
                    WatchBrandMark(size: pt(48), cornerRadius: pt(11))
                    Text(L("Secure coding-agent approvals from your wrist."))
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            Section(L("Product")) {
                LabeledContent("Version", value: AppVersion.display)
                Text(L("GrantTap is independent and is not affiliated with Apple, Anthropic, or OpenAI."))
                    .font(.caption2)
            }
            Section(L("Privacy by design")) {
                Text(L("Payloads are end-to-end encrypted. GrantTap has no account, ads, tracking, or analytics."))
                    .font(.caption2)
                Text(L("Live decisions use the paired iPhone connection."))
                    .font(.caption2)
            }
            Section {
                Text(L("© 2026 Serhii Ziborov"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L("About GrantTap"))
    }
}

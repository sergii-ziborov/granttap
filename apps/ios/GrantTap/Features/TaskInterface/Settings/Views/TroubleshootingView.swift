import SwiftUI

struct TroubleshootingView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var push: PushRegistrationManager
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
                NavigationLink {
                    ChatCacheView().environmentObject(model)
                } label: {
                    Label(L("Chat history & cache"), systemImage: "externaldrive")
                }
                .accessibilityIdentifier("settings.chat-cache")
            }
        }
        .pageNavigationTitle(L("Troubleshooting"))
        .sheet(isPresented: $showPairing) { PairingSheet().environmentObject(model) }

    }

    func readiness(_ provider: String, status: String) -> some View {
        HStack {
            Text(provider)
            Spacer()
            Text(status).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacComputerLinkView: View {
    @StateObject private var enrollment: ComputerLinkEnrollment
    @State private var link = ""

    init(model: AppModel) {
        _enrollment = StateObject(wrappedValue: ComputerLinkEnrollment(store: {
            model.addConnection($0, prefer: false)
        }, storeNetwork: { model.addControllerConnections($0) }))
    }

    var body: some View {
        List {
            Section {
                SecureField(L("Computer or device network link"), text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings.computer-link")
                Button(L("Connect computer")) {
                    Task {
                        await enrollment.connect(link)
                        if enrollment.phase == .saved { link = "" }
                    }
                }
                .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || enrollment.busy)
                .accessibilityIdentifier("settings.connect-computer")
                if enrollment.busy { ProgressView(L("Connecting…")) }
                if let message = enrollment.message {
                    Text(message).foregroundStyle(enrollment.phase == .saved ? Theme.ok : Theme.riskHigh)
                        .accessibilityIdentifier("settings.computer-link-result")
                }
            } footer: {
                Text(L("Paste a one-time link from another Mac or PC, or a device network invite from your iPhone. Existing connections stay in place."))
            }
        }
        .pageNavigationTitle(L("Connect a computer by link"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { link = "" }
    }
}
#endif

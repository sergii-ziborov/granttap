import SwiftUI

struct ControllerNetworkInviteSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var coordinator = ControllerInviteCoordinator.shared

    var body: some View {
        CompatNavigationStack {
            List {
                Section {
                    Text(L("This controller asks each connected computer for a separate, one-time key. The new iPhone or iPad joins your device network. Mesh access is granted separately."))
                        .foregroundStyle(Theme.muted)
                }
                Section(L("Computers in this invitation")) {
                    ForEach(coordinator.entries) { entry in
                        HStack {
                            Text(entry.name)
                            Spacer()
                            if entry.uri != nil {
                                Label(L("Ready"), systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.ok)
                            } else if let error = entry.error {
                                Text(error).foregroundStyle(Theme.riskHigh)
                            } else {
                                ProgressView()
                            }
                        }
                    }
                    if coordinator.entries.isEmpty {
                        Text(L("No Live computers are available."))
                            .foregroundStyle(Theme.muted)
                    }
                }
                if !coordinator.omittedComputerNames.isEmpty {
                    Section(L("Add later")) {
                        ForEach(coordinator.omittedComputerNames.indices, id: \.self) { index in
                            Text(coordinator.omittedComputerNames[index])
                                .foregroundStyle(Theme.muted)
                        }
                        Text(L("Offline computers cannot issue a new controller key. Connect them later and show a fresh QR."))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                if let uri = coordinator.bundleURI {
                    Section(L("Scan on the new iPhone or iPad")) {
                        HStack {
                            Spacer()
                            QRCodeImage(text: uri)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        Button(L("Copy one-time link")) { UIPasteboard.general.string = uri }
                        Text(L("The code can be used once and expires after 15 minutes. On the new device, open Settings → Connections → Add a device and scan it."))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                } else {
                    Section {
                        Button {
                            Task { await coordinator.publish() }
                        } label: {
                            if coordinator.publishing { ProgressView() }
                            else { Label(L("Show controller QR"), systemImage: "qrcode") }
                        }
                        .disabled(!coordinator.readyToPublish || coordinator.publishing)
                        Button(L("Retry")) { coordinator.start(using: model) }
                    }
                }
                if let error = coordinator.error {
                    Section { Text(error).foregroundStyle(Theme.riskHigh) }
                }
            }
            .navigationTitle(L("Add a controller"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .task { coordinator.start(using: model) }
        }
    }
}

import SwiftUI

/// One account may have many computer routes. The header opens this overview;
/// selecting a computer reveals its own health, load, and tools.
struct ConnectionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    var body: some View {
        CompatNavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                List {
                    Section(L("Relay")) {
                        Label(model.relayConnectionSnapshot.statusTitle, systemImage: "network")
                            .foregroundStyle(model.relayConnectionSnapshot.statusColor)
                    }
                    if model.demoMode {
                        Section {
                            Text(L("Sample data — nothing reaches a computer."))
                                .foregroundStyle(Theme.muted)
                        }
                    } else if model.connectionOverview.isEmpty {
                        Section {
                            Text(L("No computers linked. Scan a QR from any Mac/PC agent chat to add one."))
                                .foregroundStyle(Theme.muted)
                        }
                    } else {
                        Section(L("Computers")) {
                            ForEach(model.connectionOverview) { computer in
                                NavigationLink {
                                    ComputerConnectionDetailView(roomId: computer.id)
                                        .environmentObject(model)
                                } label: {
                                    computerRow(computer)
                                }
                                .accessibilityIdentifier("connection.computer.\(computer.id)")
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("Connection"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }

    private func computerRow(_ computer: LinkedComputer) -> some View {
        let snap = model.snapshotForConnection(computer)
        return VStack(alignment: .leading, spacing: 5) {
            Text(computer.lastMachineName.isEmpty ? computer.displayName : computer.lastMachineName)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 6) {
                Circle().fill(snap.statusColor).frame(width: 8, height: 8)
                Text(snap.statusTitle).foregroundStyle(snap.statusColor)
                Spacer(minLength: 4)
                Text(L("Chat list updated"))
                    .foregroundStyle(Theme.muted)
                Text(ConnectionLoadFormat.age(seconds: snap.catalogAgeSeconds))
                    .foregroundStyle(Theme.muted)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

struct MacLocalMCPSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var reader: MacLocalMCPModel
    let computer: String?
    let paired: Bool?
    let relayStatus: String?
    let phoneReachability: String?

    @ObservedObject private var access = MacNativeAccess.shared
    private let installURL = URL(string: "https://granttap.com/#install")!

    var body: some View {
        Section(L("This Mac")) {
            if let computer {
                Button(L("Authorize local Mac access")) { Task { await access.authorize() } }
                    .disabled(access.busy)
                if let error = access.lastError { Text(error).foregroundStyle(Theme.riskHigh) }
                Label(computer, systemImage: "desktopcomputer")
                    .foregroundStyle(Theme.ok)
                Text(L("GrantTap MCP is running on this Mac."))
                    .foregroundStyle(Theme.muted)
                NavigationLink {
                    MacLocalComputerDetailView(reader: reader)
                } label: {
                    Label(L("Computer activity"), systemImage: "cpu")
                }
                .accessibilityIdentifier("settings.computer-activity")
                NavigationLink {
                    ChatCacheView().environmentObject(model)
                } label: {
                    Label(L("Chat history & cache"), systemImage: "externaldrive")
                }
                .accessibilityIdentifier("settings.chat-cache")
                NavigationLink {
                    MacProviderHooksView(reader: reader)
                } label: {
                    Label(L("Codex hooks"), systemImage: "checkmark.shield")
                    Spacer()
                    Text(ProviderHookInfo.summary(reader.status?.providers?.first { $0.id == "codex" }?.hooks))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .accessibilityIdentifier("settings.codex-hooks")
            } else {
                Label(L("GrantTap MCP is unavailable"), systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                Link(L("Install GrantTap MCP"), destination: installURL)
            }
        }

        Section {
            if let paired {
                CompatLabeledContent(L("Device pairing"), value: paired ? L("Configured") : L("Not configured"))
            }
            if paired == true, let relayStatus {
                CompatLabeledContent(L("Relay"), value: statusLabel(relayStatus))
            }
            if paired == true, let phoneReachability {
                CompatLabeledContent(L("Phone"), value: statusLabel(phoneReachability))
            }
            NavigationLink {
                MacControllerEnrollmentView().environmentObject(reader)
            } label: {
                Label(L("Connect iPhone or iPad"), systemImage: "iphone.and.arrow.forward")
            }
            .disabled(computer == nil)
            .accessibilityIdentifier("settings.connect-iphone")
            NavigationLink {
                MacComputerLinkView(model: model)
            } label: {
                Label(L("Connect a computer by link"), systemImage: "desktopcomputer")
            }
            .accessibilityIdentifier("settings.add-computer-link")
            NavigationLink {
                MacDeviceNetworkView().environmentObject(reader)
            } label: {
                Label(L("Connection mode & own relay"), systemImage: "network")
            }
            .disabled(computer == nil)
            .accessibilityIdentifier("settings.device-network")
            ForEach(model.connectionRegistry.connections.filter { !$0.pairing.isHub }) { connection in
                CompatLabeledContent(connection.displayName,
                                     value: model.snapshotForConnection(connection).phase == .live
                                        ? L("Online") : L("Offline"))
            }
        } header: {
            Text(L("Device network"))
        } footer: {
            Text(L("Connect your devices here. Project Mesh membership is managed inside each Mesh."))
        }
    }

    private func statusLabel(_ value: String) -> String {
        switch value {
        case "online", "live": return L("Online")
        case "offline": return L("Offline")
        case "connecting": return L("Connecting")
        default: return L("Unknown")
        }
    }
}
#endif

#if targetEnvironment(macCatalyst)
import SwiftUI

private struct DesktopNetworkStatus: Decodable {
    struct Settings: Decodable { let mode: String; let endpoint: String; let port: Int }
    struct OwnRelay: Decodable { let installed: Bool; let running: Bool }
    let operation: String; let settings: Settings; let ownRelay: OwnRelay
}

struct MacDeviceNetworkView: View {
    @EnvironmentObject private var reader: MacLocalMCPModel
    @ObservedObject private var license = DesktopLicenseStore.shared
    @State private var mode = "managed"
    @State private var endpoint = ""
    @State private var port = "3201"
    @State private var status: DesktopNetworkStatus?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        List {
            Section(L("Connection mode")) {
                Picker(L("Mode"), selection: $mode) {
                    Text(L("Hosted service · subscription")).tag("managed")
                    Text(L("Direct · address discovery only")).tag("direct")
                    Text(L("Own relay · fully independent")).tag("selfHosted")
                }
                if mode == "managed" {
                    Text(L("Encrypted delivery, server queues and background notifications require an active Personal subscription."))
                    NavigationLink(L("Manage subscription")) { SubscriptionView() }
                } else {
                    TextField(L("Reachable TLS endpoint · wss://…"), text: $endpoint)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .accessibilityIdentifier("network.endpoint")
                    Text(mode == "direct"
                         ? L("The managed directory stores only a short-lived encrypted address. Your iPhone refreshes it while connecting; chat traffic goes to your endpoint.")
                         : L("Pair your iPhone using this endpoint. This mode does not use the managed directory or hosted relay."))
                }
                TextField(L("Local relay port"), text: $port).accessibilityIdentifier("network.port")
                Button(L("Save connection mode")) {
                    run("desktop.network_configure", input: ["mode": mode, "endpoint": endpoint, "port": port])
                }
                .disabled(mode != "managed" && !license.license.permitsOwnRelay)
                .accessibilityIdentifier("network.save")
            }
            Section {
                CompatLabeledContent(L("Installation"), value: status?.ownRelay.installed == true ? L("Installed") : L("Not installed"))
                CompatLabeledContent(L("Status"), value: status?.ownRelay.running == true ? L("Running") : L("Stopped"))
                if status?.ownRelay.installed != true {
                    Button(L("Install own relay")) { relayAction("install") }
                        .disabled(!license.license.permitsOwnRelay)
                        .accessibilityIdentifier("network.install-relay")
                } else {
                    Button(status?.ownRelay.running == true ? L("Stop relay") : L("Start relay")) {
                        relayAction(status?.ownRelay.running == true ? "stop" : "start")
                    }
                    .disabled(!license.license.permitsOwnRelay)
                    .accessibilityIdentifier("network.relay-control")
                }
                if !license.license.permitsOwnRelay {
                    Text(L("Own relay setup requires a purchased Mac license."))
                    NavigationLink(L("Mac license")) { DesktopLicenseView() }
                }
            } header: {
                Text(L("Relay on this Mac"))
            } footer: {
                Text(L("The local server listens on loopback. Configure your TLS proxy or VPN to reach it from iPhone. GrantTap does not open router ports automatically. Save the port before starting the relay."))
            }
            if let error { Section { Text(error).foregroundStyle(Theme.riskHigh) } }
        }
        .pageNavigationTitle(L("Device network"))
        .accessibilityIdentifier("network.page")
        .disabled(busy)
        .overlay { if busy { ProgressView() } }
        .task { await invoke("desktop.network_status", input: nil) }
    }

    private func relayAction(_ action: String) {
        guard license.license.permitsOwnRelay else { return }
        run("desktop.own_relay", input: ["action": action])
    }

    private func run(_ operation: String, input: [String: String]?) {
        guard !busy else { return }
        Task { await invoke(operation, input: input) }
    }

    @MainActor private func invoke(_ operation: String, input: [String: String]?) async {
        guard let socket = reader.status?.desktopEngineSocket else { return }
        busy = true
        defer { busy = false }
        do {
            let bytes = try await MacLocalMCPClient.read(socketPath: socket, operation: operation, input: input)
            let result = try JSONDecoder().decode(DesktopNetworkStatus.self, from: bytes)
            guard result.operation == operation else { throw MacLocalMCPError.incompatible }
            status = result
            mode = result.settings.mode
            endpoint = result.settings.endpoint
            port = String(result.settings.port)
            error = nil
        } catch {
            self.error = L("The network operation could not be completed. Check the local MCP version and relay log.")
        }
    }
}
#endif

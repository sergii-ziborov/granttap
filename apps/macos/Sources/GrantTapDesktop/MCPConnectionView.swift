import DesktopInspectorCore
import SwiftUI

struct MCPConnectionView: View {
    @ObservedObject var model: DesktopModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Connection").font(.largeTitle.bold())
                        Text("This Mac, its GrantTap MCP, relay, and coding providers")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh status") { model.checkLocalMCP() }
                }
                HStack(alignment: .top, spacing: 14) {
                    mcpCard
                    relayCard
                }
                if let status = model.mcpStatus {
                    Text("Devices").font(.title3.bold())
                    DesktopCard {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Computer", value: status.computer)
                            LabeledContent("Pairing", value: status.paired ? "Present" : "Not paired")
                            LabeledContent("iPhone reachability",
                                           value: status.phoneReachability.rawValue.capitalized)
                            ForEach(status.phones) { phone in
                                Divider()
                                LabeledContent(phone.name, value: phone.status.capitalized)
                            }
                        }
                    }
                    Text("Coding providers").font(.title3.bold())
                    if status.providers.isEmpty {
                        DesktopCard {
                            Text(status.supportsDesktopStatus
                                 ? "No provider status is reported."
                                 : "Provider status is unavailable from this MCP service.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                            ForEach(status.providers) { provider in
                                DesktopCard {
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack {
                                            Text(provider.id.capitalized).font(.headline)
                                            Spacer()
                                            Text(provider.status.replacingOccurrences(of: "_", with: " ").capitalized)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(provider.status == "connected" ? .green : .orange)
                                        }
                                        Text(provider.detail).font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                engineCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var mcpCard: some View {
        DesktopCard {
            VStack(alignment: .leading, spacing: 9) {
                Label("GrantTap MCP", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Text(model.mcpStatus?.version ?? "Not detected")
                    .font(.title2.bold())
                Text(model.mcpMessage).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var relayCard: some View {
        DesktopCard {
            VStack(alignment: .leading, spacing: 9) {
                Label("Relay server", systemImage: "network")
                    .font(.headline)
                Text(relayHost)
                    .font(.title2.bold())
                Text(relayDescription).font(.subheadline)
                    .foregroundStyle(model.mcpStatus?.relayStatus == .online ? .green : .secondary)
            }
        }
    }

    private var relayDescription: String {
        guard let status = model.mcpStatus else { return "Start the local GrantTap MCP to check the relay." }
        if !status.supportsDesktopStatus { return "Relay observation is unavailable from this MCP service." }
        switch status.relayStatus {
        case .online: return "Online from this Mac"
        case .offline: return "Offline from this Mac"
        case .unknown: return "Connection has not been observed"
        }
    }

    private var relayHost: String {
        guard let host = model.mcpStatus?.relayHost, !host.isEmpty else {
            return "Not reported"
        }
        return host
    }

    private var engineCard: some View {
        DesktopCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Local Engine", systemImage: "cpu").font(.headline)
                if let version = model.snapshot?.version {
                    HStack {
                        LabeledContent("Engine", value: version.engine_version)
                        LabeledContent("Cortex", value: version.cortex_version)
                        LabeledContent("Weavatrix", value: version.weavatrix_version)
                    }
                } else {
                    Text("Project records become available when the local Engine is connected.")
                        .foregroundStyle(.secondary)
                }
                DisclosureGroup("Advanced local connection") {
                    HStack {
                        TextField("Engine socket path", text: $model.socketPath)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("engineSocketPath")
                        Button("Connect Engine") { model.refresh() }
                            .disabled(model.loading)
                    }
                    .padding(.top, 8)
                }
                Text(model.message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

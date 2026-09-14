import SwiftUI

@MainActor
struct GlobalCapabilityPolicySection: View {
    let kind: CapabilityUsageKind
    @ObservedObject var model: AppModel
    @ObservedObject var catalog: CapabilityCatalogStore

    init(
        kind: CapabilityUsageKind, model: AppModel? = nil,
        catalog: CapabilityCatalogStore? = nil
    ) {
        self.kind = kind
        self.model = model ?? .shared
        self.catalog = catalog ?? .shared
    }

    var rows: [CapabilityCatalogRow] {
        catalog.rows.filter { $0.kind == kind && $0.available }
    }

    func setAllowed(_ allowed: Bool, row: CapabilityCatalogRow) {
        switch kind {
        case .mcp:
            model.setGlobalMcpAllowed(row.name, allowed: allowed, roomId: row.roomId)
        case .skill:
            model.setGlobalSkillAllowed(row.name, allowed: allowed, roomId: row.roomId)
        case .cli:
            break
        }
    }

    func computerName(_ row: CapabilityCatalogRow) -> String {
        let linked = model.connectionRegistry.connections.first { $0.id == row.roomId }
        return linked?.displayName ?? row.machine
    }

    func metadata(_ row: CapabilityCatalogRow) -> String {
        var parts = [AgentIdentity.displayName(row.provider)]
        if let workspace = row.workspace?.split(separator: "/").last, !workspace.isEmpty {
            parts.append(String(workspace))
        }
        parts.append(computerName(row))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Section {
            if kind == .cli {
                Toggle("CLI / shell", isOn: Binding(
                    get: { !model.globalShellDisabled },
                    set: { model.setGlobalShellAllowed($0) }
                ))
            } else if rows.isEmpty {
                Text(kind == .mcp ? "No MCP servers reported by a linked computer"
                                  : "No skills reported by a linked computer")
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(rows) { row in
                    Toggle(isOn: Binding(
                        get: { row.allowed },
                        set: { setAllowed($0, row: row) }
                    )) {
                        HStack(spacing: 10) {
                            ProviderArtworkImage(agent: row.provider, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind == .mcp
                                     ? MCPIdentity(name: row.name).displayName : row.name)
                                Text(metadata(row))
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        } header: {
            Text(L("Available by computer and provider"))
        } footer: {
            Text(L("Turning an item off blocks it in every task on that computer. Per-task controls cannot override a global block."))
        }
    }
}

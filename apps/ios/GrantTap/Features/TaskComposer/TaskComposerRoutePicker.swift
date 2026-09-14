import SwiftUI

struct TaskComposerComputerOption: Identifiable, Equatable {
    let id: String
    let name: String
    let phase: ConnectionPhase
}

@MainActor
struct TaskComposerRoutePicker: View {
    @ObservedObject var catalog: CapabilityCatalogStore
    @Binding var provider: String
    @Binding var computerId: String?
    @Binding var workspace: String

    let computers: [TaskComposerComputerOption]
    let workspaces: [String]
    let enabledProviders: Set<String>
    @State private var showWorkspacePicker = false

    init(
        provider: Binding<String>, computerId: Binding<String?>,
        workspace: Binding<String>, computers: [TaskComposerComputerOption],
        workspaces: [String], catalog: CapabilityCatalogStore? = nil,
        enabledProviders: Set<String> = Set(AgentIdentity.composeIds)
    ) {
        _provider = provider
        _computerId = computerId
        _workspace = workspace
        self.computers = computers
        self.workspaces = workspaces
        self.enabledProviders = enabledProviders
        self.catalog = catalog ?? .shared
    }

    var providerIds: [String] {
        AgentIdentity.composeIds.filter { enabledProviders.contains($0) }
    }

    var selectedComputer: TaskComposerComputerOption? {
        if let computerId, let match = computers.first(where: { $0.id == computerId }) {
            return match
        }
        return computers.first
    }

    var body: some View {
        HStack(spacing: 5) {
            providerMenu
            computerMenu
            workspaceMenu
        }
    }

    var providerMenu: some View {
        Menu {
            providerOptions
        } label: {
            routeLabel(
                icon: AnyView(ProviderArtworkImage(agent: provider, size: 18)),
                value: AgentIdentity.shortName(provider),
                accessibility: AgentIdentity.displayName(provider)
            )
        }
        .accessibilityLabel("Provider, \(AgentIdentity.displayName(provider))")
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder var providerOptions: some View {
        ForEach(providerIds, id: \.self) { agent in
            Button {
                provider = agent
                workspace = ""
            } label: {
                HStack {
                    ProviderArtworkImage(agent: agent, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AgentIdentity.displayName(agent))
                        Text(TaskComposerRoutePresentation.providerMetadata(
                            phase: selectedComputer?.phase ?? .notLinked,
                            mcpCount: mcpCount(for: agent)
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    if provider == agent { Image(systemName: "checkmark") }
                }
            }
        }
    }

    var computerMenu: some View {
        Menu {
            computerOptions
        } label: {
            let selected = selectedComputer
            routeLabel(
                icon: AnyView(availabilityDot(selected.map { ComputerAvailabilityTone(phase: $0.phase) } ?? .offline)),
                value: selected?.name ?? L("No computer"),
                accessibility: selected?.name ?? L("No computer")
            )
        }
        .disabled(computers.isEmpty)
        .accessibilityLabel("Computer, \(selectedComputer?.name ?? L("No computer"))")
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder var computerOptions: some View {
        ForEach(computers) { computer in
            Button { computerId = computer.id } label: {
                HStack {
                    availabilityDot(ComputerAvailabilityTone(phase: computer.phase))
                    Text(computer.name)
                    if selectedComputer?.id == computer.id { Image(systemName: "checkmark") }
                }
            }
        }
    }

    /// A person can have hundreds of project folders, so this opens a searchable
    /// list rather than a dropdown nobody can scan.
    var workspaceMenu: some View {
        Button { showWorkspacePicker = true } label: {
            routeLabel(
                icon: AnyView(Image(systemName: workspace.isEmpty ? "square.dashed" : "folder.fill")),
                value: workspace.isEmpty ? L("No project") : workspaceName(workspace),
                accessibility: workspace.isEmpty ? L("No project") : workspace
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workspace, \(workspace.isEmpty ? L("No project") : workspace)")
        .accessibilityIdentifier("composer.workspace")
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showWorkspacePicker) {
            WorkspacePickerSheet(workspaces: workspaces, workspace: $workspace)
        }
    }

    func routeLabel(icon: AnyView, value: String, accessibility: String) -> some View {
        let label = TaskComposerRouteLabel(value)
        return HStack(spacing: 4) {
            icon.frame(width: 18, height: 18)
            Text(label.compact).lineLimit(1).truncationMode(.tail)
            Image(systemName: "chevron.up")
                .font(.system(size: 8, weight: .bold))
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
        .accessibilityLabel(accessibility)
    }

    func availabilityDot(_ tone: ComputerAvailabilityTone) -> some View {
        Circle()
            .fill(tone == .live ? Theme.ok : tone == .transitional ? Theme.riskMed : Theme.riskHigh)
            .frame(width: 8, height: 8)
    }

    func workspaceName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    func mcpCount(for agent: String) -> Int {
        guard let roomId = selectedComputer?.id else { return 0 }
        return Set(catalog.rows.filter {
            $0.roomId == roomId && $0.provider == AgentIdentity.normalize(agent)
                && $0.kind == .mcp && $0.available
        }.map(\.name)).count
    }
}

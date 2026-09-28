import SwiftUI

struct ProjectCortexView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var requestedEnabled: [String: Bool] = [:]

    private var currentSnapshot: ProjectMeshSnapshot {
        model.meshSnapshots[snapshot.projectId] ?? snapshot
    }

    private var integrations: [ProjectCortexIntegration] {
        (currentSnapshot.cortex ?? []).sorted { $0.endpointId < $1.endpointId }
    }

    private var endpointIds: [String] {
        Array(Set(ProjectManagePresentation.endpointIds(currentSnapshot)
            + integrations.map(\.endpointId))).sorted()
    }

    var body: some View {
        List {
            Section {
                if endpointIds.isEmpty {
                    Text(L("No computer is linked to this Mesh. Link one to configure Cortex Loom."))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(endpointIds, id: \.self) { endpointId in
                    let integration = integrations.first { $0.endpointId == endpointId }
                    HStack(spacing: 12) {
                        NavigationLink {
                            ProjectCortexEndpointView(
                                projectId: snapshot.projectId, endpointId: endpointId,
                                integration: integration, model: model
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(computerName(endpointId))
                                    Spacer()
                                    Text(integration.map { cortexStateTitle($0.state) } ?? L("No report"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(integration.map { cortexStateColor($0.state) } ?? .orange)
                                }
                                Text(integration.map(versionLine) ?? L("This computer has not reported its Engine or Cortex status"))
                                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                                Text(statusExplanation(integration))
                                    .font(.caption2).foregroundStyle(Theme.muted).lineLimit(2)
                                if let detail = integration?.detail {
                                    Text(L(detail)).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                                }
                                if requestedEnabled[endpointId] != nil {
                                    Text(L("Requested; awaiting computer report"))
                                        .font(.caption2).foregroundStyle(.orange)
                                }
                            }
                        }
                        .accessibilityIdentifier("cortex.endpoint.\(endpointId)")
                        Toggle(L("Enabled for this Mesh"),
                               isOn: enabledBinding(endpointId, integration: integration))
                            .labelsHidden()
                    }
                }
            } header: {
                Text(L("Mesh integration"))
            } footer: {
                Text(L("Each row is one computer in this Mesh. Cortex Loom runs inside GrantTap Engine there, selects permitted task evidence and uses the bound Weavatrix repository graph. Off means disabled for this Mesh; No report means this computer has not confirmed its state."))
            }
        }
        .pageNavigationTitle(L("Cortex Loom"))
        .onChange(of: integrations) { reported in
            for (endpointId, requested) in requestedEnabled {
                if reported.first(where: { $0.endpointId == endpointId })?.enabled == requested {
                    requestedEnabled.removeValue(forKey: endpointId)
                }
            }
        }
    }

    private func enabledBinding(
        _ endpointId: String, integration: ProjectCortexIntegration?
    ) -> Binding<Bool> {
        Binding(get: { requestedEnabled[endpointId] ?? integration?.enabled ?? false },
                set: { enabled in
            requestedEnabled[endpointId] = enabled
            model.setProjectCortex(
                projectId: snapshot.projectId, endpointId: endpointId,
                configuration: .init(projectId: snapshot.projectId, enabled: enabled,
                                     maxTokens: integration?.maxTokens ?? 16_384)
            ) { acceptedByRelay in
                if !acceptedByRelay { requestedEnabled.removeValue(forKey: endpointId) }
            }
        })
    }

    private func computerName(_ endpointId: String) -> String {
        ProjectHealthDiagnostics.computerName(
            endpointId, connections: model.connectionRegistry.connections
        )
    }

    private func versionLine(_ integration: ProjectCortexIntegration) -> String {
        let cortex = integration.version.map { "Cortex \($0)" } ?? L("Cortex version unknown")
        let weavatrix = integration.weavatrixVersion.map { "Weavatrix \($0)" }
        return [cortex, weavatrix].compactMap { $0 }.joined(separator: " · ")
    }

    private func statusExplanation(_ integration: ProjectCortexIntegration?) -> String {
        guard let integration else { return L("Check this computer's connection and Mesh binding.") }
        if !integration.enabled { return L("Disabled for this Mesh on this computer.") }
        switch integration.state {
        case "succeeded": return L("A context packet was prepared; agent receipt is not reported.")
        case "loaded": return L("Library loaded; no completed packet was reported.")
        case "degraded": return L("Library ran with missing or partial evidence.")
        default: return L("Open this computer for the reported reason.")
        }
    }
}

struct ProjectCortexEndpointView: View {
    let projectId: String
    let endpointId: String
    let integration: ProjectCortexIntegration?
    @ObservedObject var model: AppModel
    @State private var enabled: Bool
    @State private var maxTokens: Int
    @State private var submission: String?

    private var currentIntegration: ProjectCortexIntegration? {
        model.meshSnapshots[projectId]?.cortex?.first { $0.endpointId == endpointId }
            ?? integration
    }

    init(projectId: String, endpointId: String,
         integration: ProjectCortexIntegration?, model: AppModel) {
        self.projectId = projectId
        self.endpointId = endpointId
        self.integration = integration
        self.model = model
        _enabled = State(initialValue: integration?.enabled ?? false)
        _maxTokens = State(initialValue: integration?.maxTokens ?? 16_384)
    }

    var body: some View {
        let integration = currentIntegration
        List {
            Section(L("What Cortex Loom does")) {
                Text(L("For a Task, it selects permitted Mesh evidence, decisions, code relations and relevant skills within a context budget. Weavatrix supplies repository evidence. Mesh policy still controls access and actions."))
                    .font(.caption)
                Text(L("Loaded means the library is present. Succeeded means a packet was prepared. Neither proves an agent received or used the packet."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Section(L("Mesh configuration")) {
                Toggle(L("Enabled for this Mesh"), isOn: $enabled)
                Stepper(value: $maxTokens, in: 512...262_144, step: 512) {
                    CompatLabeledContent(L("Context budget"), value: "\(maxTokens) tokens")
                }
                Button(L("Save Cortex configuration")) { save() }
                if let submission {
                    Text(submission).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Section(L("Loaded libraries")) {
                CompatLabeledContent(L("State"), value: integration.map {
                    cortexStateTitle($0.state)
                } ?? L("No report"))
                if let version = integration?.version {
                    CompatLabeledContent(L("Cortex"), value: version)
                }
                if let revision = integration?.revision {
                    CompatLabeledContent(L("Cortex revision"), value: revision)
                }
                if let version = integration?.weavatrixVersion {
                    CompatLabeledContent(L("Weavatrix"), value: version)
                }
                if let detail = integration?.detail {
                    Text(L(detail)).font(.caption).foregroundStyle(.orange)
                }
                CompatLabeledContent(L("Last checked"), value: integration.map {
                    ReportBuilder.stamp($0.checkedAt)
                } ?? L("No report"))
            }
            if let packet = integration?.packet {
                Section(L("Latest context packet")) {
                    if let packetId = packet.packetId {
                        CompatLabeledContent(L("Packet"), value: packetId)
                    }
                    if let snapshotId = packet.snapshotId {
                        CompatLabeledContent(L("Source snapshot"), value: snapshotId)
                    }
                    metric("Included evidence", packet.included)
                    metric("Omitted evidence", packet.omitted)
                    metric("Raw estimated tokens", packet.rawEstimatedTokens)
                    metric("Selected estimated tokens", packet.selectedEstimatedTokens)
                    metric("Omitted estimated tokens", packet.omittedEstimatedTokens)
                    metric("Deduplicated lines", packet.deduplicatedLines)
                    CompatLabeledContent(L("Needs expansion"), value: packet.requiresUpstream ? L("Yes") : L("No"))
                }
            }
        }
        .pageNavigationTitle(L("Cortex Loom"))
    }

    private func save() {
        submission = L("Submitting request…")
        model.setProjectCortex(
            projectId: projectId, endpointId: endpointId,
            configuration: .init(projectId: projectId, enabled: enabled, maxTokens: maxTokens)
        ) { acceptedByRelay in
            submission = acceptedByRelay
                ? L("Request sent. Awaiting a new computer report; application is not yet confirmed.")
                : L("Request could not be delivered to this computer.")
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        CompatLabeledContent(L(title), value: String(value))
    }
}

private func cortexStateTitle(_ state: String) -> String {
    switch state {
    case "succeeded": return L("Succeeded")
    case "loaded": return L("Loaded")
    case "degraded": return L("Partial")
    case "unavailable": return L("Unavailable")
    default: return L("Off")
    }
}

private func cortexStateColor(_ state: String) -> Color {
    state == "succeeded" || state == "loaded" ? .green : (state == "disabled" ? Theme.muted : .orange)
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

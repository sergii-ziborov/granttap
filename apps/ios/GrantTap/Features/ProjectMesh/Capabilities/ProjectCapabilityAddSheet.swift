import SwiftUI

struct ProjectCapabilityAddSheet: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ProjectCapabilityRequest.Kind = .skill
    @State private var name = ""
    @State private var source = ""
    @State private var version = ""
    @State private var targetEndpoint = ""
    @State private var artifactDigest: String? = nil

    private var endpoints: [String] {
        Array(Set((snapshot.bindings ?? []).map(\.endpointId)
            + snapshot.executions.map(\.computerId))).sorted()
    }

    var body: some View {
        CompatNavigationStack {
            List {
                Section {
                    Picker(L("Kind"), selection: $kind) {
                        ForEach(ProjectCapabilityRequest.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: kind) { _ in artifactDigest = nil }
                    TextField(L("Name"), text: $name)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: name) { _ in artifactDigest = nil }
                    TextField(L("Source or publisher"), text: $source)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(L("Version"), text: $version)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker(L("Computer"), selection: $targetEndpoint) {
                        Text(L("All bound computers")).tag("")
                        ForEach(endpoints, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: targetEndpoint) { _ in artifactDigest = nil }
                } footer: {
                    Text(L("Computers check this Mesh request against their native configuration and report a separate result. This does not install or approve executable code."))
                }
                suggestions
            }
            .navigationTitle(L("Add capability"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Add"), action: add).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder private var suggestions: some View {
        let skills = snapshot.skills ?? []
        let servers = snapshot.mcpServers ?? []
        if !skills.isEmpty || !servers.isEmpty {
            Section(L("Reported by Mesh computers")) {
                ForEach(skills) { skill in
                    Button {
                        select(.skill, skill.name, skill.source, skill.version,
                               skill.endpointId, skill.digest)
                    } label: {
                        suggestion(skill.name, kind: .skill,
                                   detail: [skill.endpointId, skill.version]
                                    .compactMap { $0 }.joined(separator: " · "))
                    }
                }
                ForEach(servers) { server in
                    Button { select(.mcp, server.name, nil, server.version,
                                    server.endpointId, server.configDigest) } label: {
                        suggestion(server.title ?? server.name, kind: .mcp,
                                   detail: [server.endpointId, server.version]
                                    .compactMap { $0 }.joined(separator: " · "))
                    }
                }
            }
        }
    }

    private func suggestion(
        _ title: String, kind: ProjectCapabilityRequest.Kind, detail: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).foregroundStyle(Theme.ink)
            Text([kind.title, detail].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func select(
        _ selectedKind: ProjectCapabilityRequest.Kind,
        _ selectedName: String, _ selectedSource: String?, _ selectedVersion: String?,
        _ endpointId: String?, _ digest: String?
    ) {
        kind = selectedKind
        name = selectedName
        source = selectedSource ?? ""
        version = selectedVersion ?? ""
        targetEndpoint = endpointId ?? ""
        artifactDigest = digest
    }

    private func add() {
        model.requestProjectCapability(
            projectId: snapshot.projectId, kind: kind, name: name,
            source: source, version: version, artifactDigest: artifactDigest,
            targetEndpointId: targetEndpoint.isEmpty ? nil : targetEndpoint
        )
        dismiss()
    }
}

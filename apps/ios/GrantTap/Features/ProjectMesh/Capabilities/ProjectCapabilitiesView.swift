import SwiftUI

struct ProjectCapabilitiesView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var showAdd = false
    #if targetEnvironment(macCatalyst)
    @State private var installedSkills: [MacLocalSkill]?
    @State private var installedSkillsError = false
    #endif

    private var currentSnapshot: ProjectMeshSnapshot {
        model.meshSnapshots[snapshot.projectId] ?? snapshot
    }

    private var mcpServers: [ProjectMcpServer] {
        currentSnapshot.mcpServers ?? []
    }

    var body: some View {
        let snapshot = currentSnapshot
        List {
            requestedSection
            catalogSections
            Section {
                if let error = model.projectPolicyErrors[snapshot.projectId] {
                    Text(error).foregroundStyle(.red)
                }
                if model.pendingProjectPolicyRevisions[snapshot.projectId] != nil {
                    Text(L("Mesh policy is waiting for computer confirmation."))
                        .foregroundStyle(Theme.muted)
                }
                NavigationLink(L("View applied policy by computer")) {
                    ProjectGovernanceView(project: snapshot.project, model: model)
                }
            } footer: {
                Text(L("Allow, Ask and Deny are Mesh rules. A configured server or local skill still needs an approved manifest and a confirmed endpoint result before it is available."))
            }
            Section(L("Shared models")) {
                let catalogs = snapshot.modelCatalog ?? []
                if catalogs.flatMap(\.models).isEmpty { empty("No shared models advertised.") }
                ForEach(catalogs) { catalog in
                    ForEach(catalog.models) { item in
                        CompatLabeledContent(item.label ?? item.modelId,
                                             value: "\(item.provider) · \(catalog.endpointId)")
                    }
                }
            }
            if let restrictions = snapshot.restrictions {
                Section(L("Imported quality rules")) {
                    ForEach(restrictions.rules) { rule in
                        CompatLabeledContent(rule.name ?? rule.kind,
                                             value: rule.limit.map(String.init) ?? rule.effect)
                    }
                }
            }
            if let environment = snapshot.environment {
                Section(L("Shared environment")) {
                    ForEach(environment.variables) { variable in
                        CompatLabeledContent(variable.key,
                                             value: variable.secret ? L("Secret") : L("Shared"))
                    }
                }
            }
        }
        .pageNavigationTitle(L("Tools & Skills")) {
            Button { showAdd = true } label: { Image(systemName: "plus") }
                .accessibilityLabel(L("Add"))
                .accessibilityIdentifier("project.tools.add")
        }
        .sheet(isPresented: $showAdd) {
            ProjectCapabilityAddSheet(snapshot: currentSnapshot, model: model)
        }
        #if targetEnvironment(macCatalyst)
        .task(id: snapshot.projectId) {
            await model.refreshLocalProjectPolicy(projectId: snapshot.projectId)
            await loadInstalledSkills()
        }
        #endif
    }

    @ViewBuilder private var catalogSections: some View {
        let snapshot = currentSnapshot
            Section {
                let reports = snapshot.cortex ?? []
                if reports.isEmpty {
                    Text(L("No Engine library report has reached this Mesh. This does not mean the libraries are absent on a Mac."))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ProjectHealthDiagnostics.computerName(
                            report.endpointId, connections: model.connectionRegistry.connections
                        ))
                        Text("Weavatrix \(report.weavatrixVersion ?? L("version not reported")) · Cortex \(report.version ?? L("version not reported"))")
                            .font(.caption).foregroundStyle(Theme.muted)
                        Text(report.enabled ? report.state : L("Cortex disabled for this Mesh"))
                            .font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
                NavigationLink(L("Open library diagnostics")) {
                    ProjectCortexView(snapshot: snapshot, model: model)
                }
            } header: {
                Text(L("Built-in Mesh intelligence"))
            } footer: {
                Text(L("Weavatrix and Cortex Loom are linked Engine libraries. They do not appear as MCP servers or Skills."))
            }
            Section(L("Skills")) {
                if snapshot.skills?.isEmpty != false {
                    empty("No Mesh skill bundle has been reported. Installed local Skills are a separate inventory.")
                }
                ForEach(snapshot.skills ?? []) { skill in
                    HStack {
                        ProjectCapabilityRow(info: .skill(skill), snapshot: snapshot, model: model)
                        Spacer(minLength: 8)
                        capabilityPolicy(.skill, name: skill.name, skill: skill)
                    }
                }
            }
            #if targetEnvironment(macCatalyst)
            Section {
                if installedSkillsError {
                    Button(L("Retry local Skills")) {
                        Task { await loadInstalledSkills() }
                    }
                } else if let installedSkills {
                    if installedSkills.isEmpty {
                        empty("No local Skills were found for this Mac and its bound repositories.")
                    }
                    ForEach(installedSkills) { skill in
                        ProjectCapabilityRow(info: .init(name: skill.name, title: skill.name,
                            kind: .skill, endpointId: model.localMCPReader?.status?.endpointId,
                            provider: nil, description: skill.description,
                            fields: [.init(title: L("Scope"), value: L("Installed on this Mac"))]),
                            snapshot: snapshot, model: model)
                    }
                } else {
                    ProgressView(L("Reading local Skills…"))
                }
            } header: {
                Text(L("Installed on this Mac"))
            } footer: {
                Text(L("Local installation is separate from Mesh sharing, policy and confirmed use."))
            }
            #endif
            Section(L("MCP servers")) {
                if mcpServers.isEmpty {
                    empty("No MCP configuration has been reported from this Mesh's computers. Check each computer's runtime and binding in Health.")
                }
                ForEach(mcpServers) { server in
                    HStack(alignment: .top) {
                        ProjectCapabilityRow(info: .server(server), snapshot: snapshot, model: model)
                        Spacer(minLength: 8)
                        capabilityPolicy(.mcp, name: server.name)
                    }
                }
            }
    }

    #if targetEnvironment(macCatalyst)
    private func loadInstalledSkills() async {
        guard let reader = model.localMCPReader else { return }
        do {
            installedSkills = try await reader.installedSkills(projectId: snapshot.projectId)
            installedSkillsError = false
        } catch {
            installedSkillsError = true
        }
    }
    #endif

    @ViewBuilder private var requestedSection: some View {
        let local = model.requestedProjectCapabilities[snapshot.projectId] ?? []
        let rows = Dictionary(
            ((currentSnapshot.capabilityRequests ?? []) + local).map { ($0.id, $0) },
            uniquingKeysWith: { left, right in
                right.requestedAt >= left.requestedAt ? right : left
            }
        ).values
        if !rows.isEmpty {
            Section(L("Requested")) {
                ForEach(rows.sorted { $0.name < $1.name }) { request in
                    NavigationLink {
                        ProjectCapabilityRequestDetailView(
                            request: request, snapshot: currentSnapshot, model: model
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(request.name)
                            Text([request.kind.title, request.version, request.source]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.muted)
                            let replies = (currentSnapshot.capabilityObservations ?? [])
                                .filter { $0.requestId == request.requestId }
                            let expired = Date().timeIntervalSince1970 * 1_000
                                - request.requestedAt >= 24 * 60 * 60 * 1_000
                            Text(replies.isEmpty
                                 ? L(expired ? "Request expired; send again" : "Waiting for computer reports")
                                 : String(format: L("%d computer results"), replies.count))
                                .font(.caption2).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(L(text)).foregroundStyle(Theme.muted)
    }

    private func capabilityPolicy(
        _ kind: ProjectCapabilityKind, name: String, skill: ProjectSharedSkill? = nil
    ) -> some View {
        let rule = ProjectGovernanceLogic.NamedRule(kind: kind, name: name)
        let projection = model.projectGovernance[snapshot.projectId]
        let effect = model.projectPolicyDrafts[snapshot.projectId]?.named[rule]
            ?? ProjectGovernanceLogic.namedEffects(projection?.policy)[rule]
        return Menu {
            ForEach([ProjectPolicyEffect.ask, .deny], id: \.self) { choice in
                Button(ProjectGovernancePresentation.effectLabel(choice)) {
                    model.setProjectCapabilityEffect(
                        projectId: snapshot.projectId, kind: kind,
                        name: name, effect: choice
                    )
                }
            }
            if let skill, skill.digest != nil, skill.endpointId != nil,
               skill.state == "discovered" {
                Button(L("Approve exact bundle")) {
                    model.approveProjectSkillBundle(projectId: snapshot.projectId, skill: skill)
                }
            }
        } label: {
            Text(effect.map(ProjectGovernancePresentation.effectLabel) ?? L("Mesh rule"))
                .font(.caption).foregroundStyle(Theme.codex)
        }
        .disabled(model.demoMode || model.pendingProjectPolicyRevisions[snapshot.projectId] != nil)
    }
}

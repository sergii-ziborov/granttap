import SwiftUI
import UIKit

struct AgentsMeshSettingsSection: View {
    @ObservedObject var model: AppModel
    @State private var providerToDisable: String?

    init(model: AppModel, pendingDisable: String? = nil) {
        self.model = model
        _providerToDisable = State(initialValue: pendingDisable)
    }

    var body: some View {
        Section(L("Agents & Mesh")) {
            ForEach(AgentIdentity.knownIds, id: \.self) { provider in
                Toggle(
                    AgentIdentity.displayName(provider),
                    isOn: providerBinding(provider)
                )
            }
            NavigationLink {
                GrokBotSettingsView(model: model)
            } label: {
                HStack {
                    Text("Grok Bot")
                    Spacer()
                    Text(grokBotStatus).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Toggle("Project Mesh", isOn: meshBinding)
        }
        .confirmationDialog(
            providerToDisable.map { "Disable \(AgentIdentity.displayName($0))?" }
                ?? "Disable agent?",
            isPresented: Binding(
                get: { providerToDisable != nil },
                set: { if !$0 { providerToDisable = nil } }
            ), titleVisibility: .visible
        ) {
            if let provider = providerToDisable {
                Button("Disable \(AgentIdentity.displayName(provider))", role: .destructive) {
                    model.setProviderEnabled(provider, enabled: false)
                    providerToDisable = nil
                }
            }
            Button(L("Cancel"), role: .cancel) { providerToDisable = nil }
        } message: {
            Text(L("Pending decisions stay pending. GrantTap stops new monitoring without uninstalling the agent or deleting history."))
        }
    }

    var grokBotStatus: String {
        guard let connection = model.grokBotConnection,
              connection.credential.status == "active" else { return "Not connected" }
        return connection.endpoint.status == "active" ? "Connected" : "Connecting"
    }

    func providerBinding(_ provider: String) -> Binding<Bool> {
        Binding(
            get: { model.agentMeshPreferences.isProviderEnabled(provider) },
            set: { enabled in
                if enabled {
                    model.setProviderEnabled(provider, enabled: true)
                } else if model.providerDisableRequiresConfirmation(provider) {
                    providerToDisable = provider
                } else {
                    model.setProviderEnabled(provider, enabled: false)
                }
            }
        )
    }

    var meshBinding: Binding<Bool> {
        Binding(
            get: { model.agentMeshPreferences.meshEnabled },
            set: { model.setProjectMeshEnabled($0) }
        )
    }
}

struct GrokBotSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var showInvite = false
    @State private var confirmRevoke = false

    var body: some View {
        List {
            if let connection = activeConnection {
                Section(L("Connection")) {
                    CompatLabeledContent("Status", value: connection.endpoint.status == "active"
                                         ? "Active" : "Connecting")
                    CompatLabeledContent("Allowed projects", value: "\(connection.credential.projectIds.count)")
                }
                Section {
                    ForEach(connection.actors) { actor in
                        Toggle(actor.displayName, isOn: actorBinding(actor.actorId))
                    }
                } header: {
                    Text(L("Actors"))
                } footer: {
                    Text(L("Actors share one Grok Bot trust endpoint; toggles control Mesh routing, not isolation inside Grok Bot."))
                }
                Section {
                    Button(L("Revoke connection"), role: .destructive) { confirmRevoke = true }
                }
            } else {
                Section {
                    Button(L("Add Grok Bot")) { showInvite = true }
                        .disabled(!model.agentMeshPreferences.meshEnabled || model.meshSnapshots.isEmpty)
                } footer: {
                    Text(L("Creates a one-time encrypted invite scoped only to Projects you select. The MCP model cannot create invites or expand access."))
                }
            }
        }
        .navigationTitle("Grok Bot")
        .sheet(isPresented: $showInvite) { GrokBotInviteView(model: model) }
        .confirmationDialog("Revoke Grok Bot connection?", isPresented: $confirmRevoke,
                            titleVisibility: .visible) {
            Button(L("Revoke connection"), role: .destructive) { model.revokeGrokBotConnection() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("New Mesh operations and handoffs stop immediately. Existing Task history stays on this device."))
        }
    }

    var activeConnection: GrokBotEndpointConnection? {
        guard let connection = model.grokBotConnection,
              connection.credential.status == "active" else { return nil }
        return connection
    }

    func actorBinding(_ actorId: String) -> Binding<Bool> {
        Binding(
            get: { model.grokBotConnection?.actors.first(where: { $0.actorId == actorId })?.enabled ?? false },
            set: { model.setGrokBotActorEnabled(actorId, enabled: $0) }
        )
    }
}

struct GrokBotInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var selectedProjects: Set<String> = []
    @State private var invite: String
    @State private var error: String
    @State private var generating = false

    init(model: AppModel, issuedInvite: String = "", failure: String = "") {
        self.model = model
        _invite = State(initialValue: issuedInvite)
        _error = State(initialValue: failure)
    }

    var projects: [ProjectMeshSnapshot] {
        model.meshSnapshots.values.sorted { $0.project.name < $1.project.name }
    }

    var body: some View {
        CompatNavigationStack {
            List {
                Section(L("Allowed projects")) {
                    ForEach(projects) { snapshot in
                        Toggle(snapshot.project.name, isOn: projectBinding(snapshot.projectId))
                    }
                }
                if !invite.isEmpty {
                    Section {
                        Text(invite).font(.caption.monospaced()).textSelection(.enabled)
                        Button(L("Copy invite")) { UIPasteboard.general.string = invite }
                    } header: {
                        Text(L("One-time Mesh Invite"))
                    } footer: {
                        Text(L("Use this once with the trusted GrantTap connection flow in Grok Bot. It expires after 15 minutes."))
                    }
                } else {
                    Section {
                        Button(generating ? "Creating invite…" : "Create one-time invite") {
                            generate()
                        }
                        .disabled(selectedProjects.isEmpty || generating)
                    }
                }
                if !error.isEmpty { Text(error).foregroundStyle(Theme.riskHigh) }
            }
            .navigationTitle(L("Add Grok Bot"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
            .onAppear {
                if selectedProjects.isEmpty, let first = projects.first {
                    selectedProjects = [first.projectId]
                }
            }
        }
    }

    func projectBinding(_ projectId: String) -> Binding<Bool> {
        Binding(
            get: { selectedProjects.contains(projectId) },
            set: { enabled in
                if enabled { selectedProjects.insert(projectId) }
                else { selectedProjects.remove(projectId) }
            }
        )
    }

    func generate() {
        generating = true
        error = ""
        Task {
            do { invite = try await model.createGrokBotInvite(projectIds: selectedProjects) }
            catch { self.error = error.localizedDescription }
            generating = false
        }
    }
}

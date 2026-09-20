import SwiftUI

/// Shared Project environment. Secret values stay on the Mesh, not in git.
struct ProjectEnvironmentView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var variables: [ProjectEnvVar]
    @State private var shareNonSecrets: Bool
    @State private var draftKey = ""
    @State private var draftValue = ""
    @State private var draftSecret = false

    init(snapshot: ProjectMeshSnapshot, model: AppModel) {
        self.snapshot = snapshot
        self.model = model
        let current = snapshot.environment
            ?? model.projectGovernance[snapshot.projectId]?.policy?.environment
        _variables = State(initialValue: current?.variables ?? [])
        _shareNonSecrets = State(initialValue: current?.shareNonSecretsWithRepo ?? false)
    }

    var body: some View {
        List {
            Section {
                Toggle(L("Share non-secrets with the repository"), isOn: $shareNonSecrets)
                    .disabled(model.demoMode)
            } footer: {
                Text(L("Writes .granttap/env for non-secret keys only. Secrets never leave the Mesh."))
            }
            Section {
                ForEach(variables) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.key)
                            Text(item.secret ? L("Secret") : (item.value ?? "—"))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            variables.removeAll { $0.key == item.key }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(model.demoMode)
                    }
                    .accessibilityIdentifier("project.env.\(item.key)")
                }
                if !model.demoMode {
                    TextField(L("KEY"), text: $draftKey)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    SecureField(L("Value"), text: $draftValue)
                    Toggle(L("Secret"), isOn: $draftSecret)
                    Button(L("Add variable")) {
                        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        guard ProjectEnvironmentPresentation.isValidKey(key),
                              !variables.contains(where: { $0.key == key }) else { return }
                        variables.append(ProjectEnvVar(key: key, value: draftValue, secret: draftSecret))
                        draftKey = ""
                        draftValue = ""
                        draftSecret = false
                    }
                    .disabled(!ProjectEnvironmentPresentation.isValidKey(
                        draftKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    ))
                    .accessibilityIdentifier("project.env.add")
                }
                Button(L("Save environment")) {
                    _ = model.applyProjectEnvironment(
                        projectId: snapshot.projectId,
                        environment: ProjectEnvironment(
                            projectId: snapshot.projectId,
                            revision: 1,
                            shareNonSecretsWithRepo: shareNonSecrets,
                            variables: variables
                        )
                    )
                }
                .disabled(model.demoMode)
                .accessibilityIdentifier("project.env.save")
            } header: {
                Text(L("Variables"))
            } footer: {
                Text(statusDetail)
            }
        }
        .navigationTitle(L("Environment"))
    }

    var statusDetail: String {
        if let error = model.projectPolicyErrors[snapshot.projectId] { return error }
        return ProjectEnvironmentPresentation.summary(
            snapshot, governance: model.projectGovernance[snapshot.projectId]
        )
    }
}

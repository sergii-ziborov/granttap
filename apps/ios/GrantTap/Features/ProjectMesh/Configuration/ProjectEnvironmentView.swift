import SwiftUI

struct ProjectEnvironmentView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var variables: [ProjectEnvironmentVariable]
    @State private var shareNonSecrets: Bool
    @State private var key = ""
    @State private var value = ""
    @State private var secret = false
    @State private var editing: ProjectEnvironmentVariable?

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
                Text(L("Saving sends these KEY=VALUE pairs to computers currently bound to this Mesh. New agent processes receive them after that computer applies the policy. Linked Mesh spaces keep separate values."))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            Section {
                Toggle(L("Export non-secrets to .granttap/env"), isOn: $shareNonSecrets)
            } footer: {
                Text(L("Export writes a managed file in each bound checkout. It does not commit or push to Git. Secret values stay out of that file."))
            }
            Section(L("Mesh variables")) {
                ForEach(variables) { item in
                    HStack {
                        Button { editing = item } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.key)
                                Text(item.secret ? L("Secret · tap to replace") : (item.value ?? L("No value")))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(role: .destructive) {
                            variables.removeAll { $0.key == item.key }
                        } label: { Image(systemName: "trash") }
                    }
                }
                TextField(L("KEY"), text: $key)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                if !key.isEmpty && !validKey {
                    Text(L("Use a valid application key. Agent runtime keys such as OPENAI_* and GRANTTAP_* are reserved."))
                        .font(.caption).foregroundStyle(Theme.riskHigh)
                }
                if secret {
                    SecureField(L("Value or secret reference"), text: $value)
                } else {
                    TextField(L("Value"), text: $value)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Toggle(L("Secret value"), isOn: $secret)
                Text(L("Secret values are masked in Mesh status but injected into agent processes. An agent with shell access can read them."))
                    .font(.caption).foregroundStyle(Theme.muted)
                Button(L("Add variable"), action: add)
                    .disabled(!validKey || value.isEmpty || value.count > 4_096
                              || variables.contains { $0.key == normalizedKey })
            }
            Section {
                Button(L("Save environment")) {
                    _ = model.applyProjectEnvironment(
                        projectId: snapshot.projectId,
                        shareNonSecrets: shareNonSecrets, variables: variables
                    )
                }
                .disabled(model.projectGovernance[snapshot.projectId] == nil)
            } footer: {
                Text(model.projectPolicyErrors[snapshot.projectId]
                     ?? L("Saved policy is sent to each bound computer. Check its acknowledgement before relying on a new value."))
            }
        }
        .pageNavigationTitle(L("Environment variables"))
        .sheet(item: $editing) { item in
            ProjectEnvironmentVariableEditor(item: item) { updated in
                guard let index = variables.firstIndex(where: { $0.key == updated.key }) else { return }
                variables[index] = updated
            }
        }
    }

    private var normalizedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var validKey: Bool {
        ProjectEnvironmentKey.allowed(normalizedKey)
    }

    private func add() {
        guard validKey, !variables.contains(where: { $0.key == normalizedKey }) else { return }
        variables.append(ProjectEnvironmentVariable(key: normalizedKey, value: value, secret: secret))
        key = ""
        value = ""
        secret = false
    }
}

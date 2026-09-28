import SwiftUI

struct ProjectEnvironmentVariableEditor: View {
    let item: ProjectEnvironmentVariable
    let onSave: (ProjectEnvironmentVariable) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    @State private var secret: Bool

    init(item: ProjectEnvironmentVariable, onSave: @escaping (ProjectEnvironmentVariable) -> Void) {
        self.item = item
        self.onSave = onSave
        _value = State(initialValue: Self.initialValue(for: item))
        _secret = State(initialValue: item.secret)
    }

    private var draft: ProjectEnvironmentVariable? {
        Self.updated(item, value: value, secret: secret)
    }

    static func initialValue(for item: ProjectEnvironmentVariable) -> String {
        item.secret ? "" : (item.value ?? "")
    }

    static func updated(
        _ item: ProjectEnvironmentVariable, value: String, secret: Bool
    ) -> ProjectEnvironmentVariable? {
        if item.secret && secret && value.isEmpty { return item }
        guard !value.isEmpty, value.count <= 4_096 else { return nil }
        return ProjectEnvironmentVariable(key: item.key, value: value, secret: secret)
    }

    var body: some View {
        CompatNavigationStack {
            List {
                Section {
                    CompatLabeledContent(L("Key"), value: item.key)
                    Toggle(L("Secret value"), isOn: $secret)
                    if secret {
                        SecureField(L("New secret or reference"), text: $value)
                    } else {
                        TextField(L("Value"), text: $value)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } footer: {
                    Text(item.secret
                         ? L("The existing secret is never revealed here. Leave the field empty to keep it, or enter a replacement.")
                         : L("A non-secret value may be shared with the repository when that Mesh option is enabled."))
                }
            }
            .navigationTitle(item.key)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) {
                        guard let draft else { return }
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft == nil)
                }
            }
        }
    }
}

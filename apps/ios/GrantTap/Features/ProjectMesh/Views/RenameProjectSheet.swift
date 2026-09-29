import SwiftUI

/// A name of the person's own for a Project, kept on this phone.
struct RenameProjectSheet: View {
    let row: ProjectListRow
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(row: ProjectListRow, model: AppModel) {
        self.row = row
        self.model = model
        _name = State(initialValue: row.name)
    }

    var repositoryName: String {
        model.meshSnapshots[row.projectId].map { ProjectsCatalog.displayName($0, preference: nil) } ?? row.name
    }

    var body: some View {
        CompatNavigationStack {
            List {
                Section {
                    TextField(L("Name"), text: $name)
                        .accessibilityIdentifier("projects.rename.field")
                } footer: {
                    Text(String(format: L("Its reported name is “%@”. This name is shown only on this device."), repositoryName))
                }
                if name.trimmingCharacters(in: .whitespacesAndNewlines) != repositoryName {
                    Section {
                        Button(L("Use reported name")) {
                            model.renameProject(row.projectId, to: "")
                            dismiss()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("Rename Mesh"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) {
                        model.renameProject(row.projectId, to: name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("projects.rename.save")
                }
            }
        }
    }
}

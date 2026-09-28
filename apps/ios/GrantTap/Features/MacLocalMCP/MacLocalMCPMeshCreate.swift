#if targetEnvironment(macCatalyst)
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct MacLocalMeshCreateResult: Decodable, Sendable {
    let operation: String
    let created: Bool
    let project_id: String
    let error: String?
}

extension MacLocalMCPModel {
    func createMesh(name: String, repositoryPath: String) async throws -> MacLocalMeshCreateResult {
        guard let socket = status?.desktopEngineSocket else { throw MacLocalMCPError.unavailable }
        let data = try await MacLocalMCPClient.read(
            socketPath: socket, operation: "desktop.mesh_create",
            input: ["name": name, "repository_path": repositoryPath]
        )
        let result = try JSONDecoder().decode(MacLocalMeshCreateResult.self, from: data)
        guard result.operation == "desktop.mesh_create", !result.project_id.isEmpty,
              (result.error?.count ?? 0) <= 500 else { throw MacLocalMCPError.incompatible }
        return result
    }
}

struct MacNewMeshView: View {
    @ObservedObject var reader: MacLocalMCPModel
    var onCreated: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var repositoryPath = ""
    @State private var showFolderPicker = false
    @State private var creating = false
    @State private var errorText: String?

    var body: some View {
        CompatNavigationStack {
            Form {
                Section {
                    TextField(L("Mesh name"), text: $name)
                    Button {
                        showFolderPicker = true
                    } label: {
                        Label(repositoryPath.isEmpty ? L("Choose a repository folder")
                              : repositoryPath, systemImage: "folder")
                            .lineLimit(1)
                    }
                } header: {
                    Text(L("Mesh"))
                } footer: {
                    Text(L("A Mesh can connect several repositories. Start with one local Git repository."))
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Theme.riskHigh) }
                }
            }
            .navigationTitle(L("New Mesh"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Create")) { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || repositoryPath.isEmpty || creating)
                }
            }
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                if case let .success(url) = result { repositoryPath = url.path }
            }
        }
        .frame(width: 620, height: 360)
    }

    private func create() async {
        guard !creating else { return }
        creating = true
        defer { creating = false }
        do {
            let result = try await reader.createMesh(name: name, repositoryPath: repositoryPath)
            guard result.created else {
                errorText = result.error ?? L("This repository already belongs to a Mesh.")
                return
            }
            await onCreated()
            dismiss()
        } catch {
            errorText = L("Could not create this Mesh. Choose a local Git repository and retry.")
        }
    }
}
#endif

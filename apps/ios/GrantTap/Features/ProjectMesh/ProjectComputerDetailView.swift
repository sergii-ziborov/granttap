import SwiftUI

/// One computer in this Project: what it is doing, archive, remove, unlink.
struct ProjectComputerDetailView: View {
    let endpointId: String
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false
    @State private var confirmUnlink = false

    private var disposition: ProjectComputerDisposition {
        model.computerDisposition(endpointId, projectId: snapshot.projectId)
    }

    private var connection: LinkedComputer? {
        model.connection(matching: endpointId)
    }

    var body: some View {
        List {
            Section {
                CompatLabeledContent(L("Computer"), value: model.displayName(forComputer: endpointId))
                if let connection {
                    CompatLabeledContent(
                        L("Status"),
                        value: model.snapshotForConnection(connection).statusTitle
                    )
                }
                CompatLabeledContent(L("In this Project"), value: dispositionLabel)
                if let line = ProjectComputerWork.line(
                    ProjectComputerWork.current(
                        snapshot: snapshot, endpointId: endpointId, sessions: model.sessions
                    )
                ) {
                    Text(line).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Section {
                NavigationLink {
                    ProjectComputerUsageView(
                        endpointId: endpointId, snapshot: snapshot, model: model
                    )
                } label: {
                    Text(L("Usage on this computer"))
                }
                .accessibilityIdentifier("computer.usage.\(endpointId)")
            }
            Section {
                if disposition == .archived {
                    Button(L("Restore to this Project")) {
                        _ = model.restoreProjectComputer(
                            projectId: snapshot.projectId, endpointId: endpointId
                        )
                    }
                    .accessibilityIdentifier("computer.restore.\(endpointId)")
                } else if disposition == .active {
                    Button(L("Archive in this Project")) {
                        _ = model.archiveProjectComputer(
                            projectId: snapshot.projectId, endpointId: endpointId
                        )
                    }
                    .accessibilityIdentifier("computer.archive.\(endpointId)")
                }
                if disposition != .removed {
                    Button(L("Remove from this Project"), role: .destructive) {
                        confirmRemove = true
                    }
                    .accessibilityIdentifier("computer.remove.\(endpointId)")
                }
                if connection != nil {
                    Button(L("Unlink this computer"), role: .destructive) {
                        confirmUnlink = true
                    }
                    .accessibilityIdentifier("computer.unlink.\(endpointId)")
                }
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle(model.displayName(forComputer: endpointId))
        .confirmationDialog(
            L("Remove from this Project?"),
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button(L("Remove from this Project"), role: .destructive) {
                _ = model.removeProjectComputer(
                    projectId: snapshot.projectId, endpointId: endpointId
                )
                dismiss()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The computer stays paired. This Project no longer sends it the mesh key."))
        }
        .confirmationDialog(
            L("Unlink this computer?"),
            isPresented: $confirmUnlink,
            titleVisibility: .visible
        ) {
            Button(L("Unlink"), role: .destructive) {
                model.unlinkProjectComputer(
                    projectId: snapshot.projectId, endpointId: endpointId
                )
                dismiss()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Unlinking removes the pairing from this iPhone."))
        }
    }

    private var dispositionLabel: String {
        switch disposition {
        case .active: return L("Taking part")
        case .archived: return L("Archived")
        case .removed: return L("Removed from Project")
        }
    }

    private var footer: String {
        switch disposition {
        case .active:
            return L("Archive hides this computer from Execution and Members. Remove takes it out of this Project.")
        case .archived:
            return L("Archived computers stay in Mesh statistics. Restore puts this one back in the working set.")
        case .removed:
            return L("Add this computer again from Members if it is still paired.")
        }
    }
}

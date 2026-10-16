import SwiftUI

struct ProjectNetworkRoutingControl: View {
    let projectId: String
    @ObservedObject var model: AppModel
    @ObservedObject private var coordinator: ProjectNetworkCoordinator
    @State private var failed = false

    init(projectId: String, model: AppModel) {
        self.projectId = projectId
        self.model = model
        self.coordinator = model.computerNetwork
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L("Automatic computer transfers"), isOn: Binding(
                get: { coordinator.routingEnabled(projectId: projectId) },
                set: { enabled in
                    Task {
                        failed = false
                        do { try await model.configureProjectComputerNetwork(projectId: projectId, routingEnabled: enabled) }
                        catch { failed = true }
                    }
                }))
                .disabled(!model.agentMeshPreferences.meshEnabled || coordinator.states[projectId] == .configuring)
            Text(L("Uses compatible computers in this Mesh while preserving the provider, model and effort."))
                .font(.caption).foregroundStyle(Theme.muted)
            if coordinator.routingEnabled(projectId: projectId) {
                Toggle(L("Allow portable work across platforms"), isOn: Binding(
                    get: { coordinator.allowsCrossPlatform(projectId: projectId) },
                    set: { enabled in
                        Task {
                            failed = false
                            do { try await model.configureProjectComputerNetwork(projectId: projectId, allowCrossPlatform: enabled) }
                            catch { failed = true }
                        }
                    }))
                    .disabled(!model.agentMeshPreferences.meshEnabled || coordinator.states[projectId] == .configuring)
                Text(L("Only tasks declared portable can move between macOS, Windows and Linux."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if coordinator.states[projectId] == .configuring {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Waiting for computer confirmation")).font(.caption)
                }
            } else if failed || coordinator.states[projectId] == .failed {
                Text(L("Transfer settings could not be confirmed. Check the computers and try again."))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

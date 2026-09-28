import SwiftUI

/// The Project-scoped controls a computer can enforce: whether new work is
/// routed here and the filesystem access of executions already running here.
struct ProjectComputerAccessView: View {
    let snapshot: ProjectMeshSnapshot
    let computer: ProjectComputerSummary
    @ObservedObject var model: AppModel
    @State private var access = "workspace"

    private var policy: ProjectExecutionPolicy? {
        model.projectGovernance[snapshot.projectId]?.policy?.execution ?? snapshot.execution
    }

    private var sessions: [SessionInfo] {
        let executionIds = Set(snapshot.executions.filter {
            $0.computerId == computer.endpointId && $0.endedAt == nil
        }.map { model.resolvedSessionId($0.sessionId) })
        return model.sessions.filter {
            executionIds.contains(model.resolvedSessionId($0.sessionId))
        }
    }

    private var isDefaultHost: Bool { policy?.targetEndpointId == computer.endpointId }

    var body: some View {
        List {
            Section {
                CompatLabeledContent(L("Role"), value: role)
                CompatLabeledContent(
                    L("Availability"),
                    value: computer.available ? L("Online") : L("Offline")
                )
                CompatLabeledContent(
                    L("Repositories"), value: String(computer.repositoryCount)
                )
                Button(isDefaultHost ? L("Use distributed execution") : L("Make default execution computer")) {
                    _ = model.setProjectExecutionHost(
                        projectId: snapshot.projectId,
                        endpointId: isDefaultHost ? nil : computer.endpointId
                    )
                }
                .disabled(model.projectGovernance[snapshot.projectId] == nil)
            } header: {
                Text(L("Mesh role"))
            } footer: {
                Text(L("A default execution computer receives new Mesh tasks unless a task chooses another host."))
            }

            Section {
                Picker(L("Task access"), selection: $access) {
                    Text(L("Read only")).tag("read-only")
                    Text(L("Workspace")).tag("workspace")
                    Text(L("Full access")).tag("full")
                }
                .disabled(sessions.isEmpty)
                if sessions.isEmpty {
                    Text(L("No active execution on this computer."))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(sessions) { session in
                        HStack {
                            Text(session.displayTitle).lineLimit(1)
                            Spacer()
                            Text(accessTitle(session.accessLevel ?? "workspace"))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            } header: {
                Text(L("Device access"))
            } footer: {
                Text(L("The computer enforces this access for every active Mesh task running on it."))
            }
        }
        .pageNavigationTitle(computer.displayName)
        .onAppear { access = commonAccess }
        .onChange(of: access) { value in
            for session in sessions where session.accessLevel != value {
                model.setSessionAccess(session.sessionId, value)
            }
        }
    }

    private var commonAccess: String {
        let levels = Set(sessions.map { $0.accessLevel ?? "workspace" })
        return levels.count == 1 ? levels.first ?? "workspace" : "workspace"
    }

    private var role: String {
        if isDefaultHost { return L("Default execution host") }
        if snapshot.executions.contains(where: {
            $0.computerId == computer.endpointId && $0.endedAt == nil
        }) { return L("Execution host") }
        return L("Mesh member")
    }

    private func accessTitle(_ level: String) -> String {
        switch level {
        case "read-only": return L("Read only")
        case "full": return L("Full access")
        default: return L("Workspace")
        }
    }
}

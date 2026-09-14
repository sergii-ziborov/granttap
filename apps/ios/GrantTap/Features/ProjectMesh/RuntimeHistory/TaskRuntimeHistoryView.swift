import SwiftUI

extension TaskRouteView {
    private var runtimeKey: String {
        AppModel.invocationTaskKey(route.projectId, route.taskId)
    }

    @ViewBuilder
    var runtimeSection: some View {
        Section {
            let records = model.invocationHistoryByTask[runtimeKey] ?? []
            if records.isEmpty {
                Text(runtimeEmptyMessage)
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            ForEach(Array(records.suffix(20).reversed())) { row in
                runtimeRow(row)
            }
            if model.hasOlderInvocations(projectId: route.projectId, taskId: route.taskId) {
                Button(L("Show older activity")) {
                    model.requestInvocationHistory(
                        projectId: route.projectId, taskId: route.taskId, older: true
                    )
                }
            }
        } header: {
            HStack {
                Text(L("Runtime"))
                Spacer()
                Button {
                    model.refreshInvocationHistory(projectId: route.projectId, taskId: route.taskId)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(L("Refresh runtime activity"))
            }
        } footer: {
            Text(L("Tool results come from the agent transcript. Only a separately verified file observation proves a change."))
        }
    }

    private var runtimeEmptyMessage: String {
        switch model.invocationAvailabilityByTask[runtimeKey] {
        case "unavailable": return L("Runtime history is unavailable on this computer.")
        case "offline": return L("Connect a project computer to load runtime history.")
        case "ready": return L("No observed tool calls for this task yet.")
        default: return L("Loading runtime activity…")
        }
    }

    @ViewBuilder
    private func runtimeRow(_ row: ProjectInvocationRecord) -> some View {
        let event = row.event
        let matchingExecution = executions.first { $0.sessionId == event.session_id }
        if let matchingExecution, session(for: matchingExecution) != nil {
            Button {
                dismiss()
                openChat(for: matchingExecution)
            } label: {
                runtimeContent(event, chatAvailable: true)
            }
            .buttonStyle(.plain)
        } else {
            runtimeContent(event, chatAvailable: false)
        }
    }

    private func runtimeContent(
        _ event: ProjectInvocationEvent, chatAvailable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.tool_name).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(runtimePhase(event.phase))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(event.phase == "reported_failure" || event.phase == "denied"
                                     ? Theme.riskHigh : Theme.muted)
            }
            Text("\(event.provider) · \(ReportBuilder.stamp(event.occurred_at))")
                .font(.caption2).foregroundStyle(Theme.muted)
            if let resource = event.resource {
                Text(resource).font(.system(size: 12, design: .monospaced))
            }
            if event.phase == "change_observed", let repository = event.repository_id {
                Text(String(format: L("Verified in repository %@ at revision %@"),
                            repository, event.revision ?? ""))
                    .font(.caption2).foregroundStyle(Theme.muted)
            }
            if event.phase == "denied", let rule = event.policy_rule_id {
                Text(String(format: L("Project rule: %@"), rule))
                    .font(.caption2).foregroundStyle(Theme.muted)
            }
            if chatAvailable {
                Label(L("Open chat"), systemImage: "bubble.left")
                    .font(.caption2).foregroundStyle(Theme.codex)
            }
        }
    }

    private func runtimePhase(_ phase: String) -> String {
        switch phase {
        case "requested": return L("Requested")
        case "reported_success": return L("Reported success")
        case "reported_failure": return L("Reported failure")
        case "reported_unknown": return L("Outcome unknown")
        case "denied": return L("Denied")
        case "change_observed": return L("Change verified")
        case "source_gap": return L("History gap")
        default: return L("Unknown")
        }
    }
}

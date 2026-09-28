import DesktopInspectorCore
import Foundation
import SwiftUI

struct DesktopTaskItem: Identifiable {
    let projectId: String
    let projectName: String
    let taskId: String
    let title: String
    let state: String
    let provider: String?
    let updatedAt: Double
    let hasOpenExecution: Bool
    let lastExecutionActiveAt: Double?

    var id: String { "\(projectId):\(taskId)" }
    var isFinished: Bool { state == "completed" || state == "failed" }
    var needsYou: Bool { state == "needs_user" }
    var isWorking: Bool { (state == "working" || state == "handoff") && hasOpenExecution }
    var isBlocked: Bool { state == "blocked" }
    var isRecentlyUpdated: Bool {
        guard isWorking, let lastExecutionActiveAt, lastExecutionActiveAt > 0 else { return false }
        let seconds = lastExecutionActiveAt > 10_000_000_000
            ? lastExecutionActiveAt / 1_000 : lastExecutionActiveAt
        return abs(Date().timeIntervalSince1970 - seconds) < 15 * 60
    }
    var isLastKnownWorking: Bool { isWorking && !isRecentlyUpdated }

    var stateLabel: String {
        switch state {
        case "needs_user": "Needs You"
        case "working" where isRecentlyUpdated: "Working"
        case "working" where hasOpenExecution: "At Risk"
        case "working": "Idle"
        case "handoff": "Handoff reported"
        case "blocked": "Blocked"
        case "planned": "Planned"
        case "completed": "Finished"
        case "failed": "Failed"
        default: state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var stateColor: Color {
        switch state {
        case "working" where isRecentlyUpdated: DesktopTheme.positive
        case "working" where hasOpenExecution: DesktopTheme.caution
        case "working": DesktopTheme.muted
        case "needs_user", "failed": DesktopTheme.danger
        case "blocked", "handoff": DesktopTheme.caution
        default: DesktopTheme.muted
        }
    }

    var lastActive: String? {
        let time = hasOpenExecution ? lastExecutionActiveAt ?? updatedAt : updatedAt
        guard time > 0 else { return nil }
        let seconds = time > 10_000_000_000 ? time / 1_000 : time
        let date = Date(timeIntervalSince1970: seconds)
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }
}

enum DesktopTaskCatalog {
    static func items(workspace: MeshWorkspaceSummary?, mesh: MeshProjectSnapshot?,
                      projectName: String?) -> [DesktopTaskItem] {
        if let workspace {
            return workspace.tasks.map { task in
                DesktopTaskItem(projectId: task.project_id, projectName: task.project_name,
                                taskId: task.task_id, title: task.title, state: task.state,
                                provider: task.provider, updatedAt: task.updated_at,
                                hasOpenExecution: task.has_open_execution ?? false,
                                lastExecutionActiveAt: task.last_execution_active_at)
            }.sorted { $0.updatedAt > $1.updatedAt }
        }
        guard let mesh else { return [] }
        return mesh.tasks.map { task in
            DesktopTaskItem(projectId: mesh.project_id, projectName: projectName ?? "Project",
                            taskId: task.task_id, title: task.title, state: task.state,
                            provider: task.provider, updatedAt: task.updated_at,
                            hasOpenExecution: task.has_open_execution ?? false,
                            lastExecutionActiveAt: task.last_execution_active_at)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
}

struct DesktopTaskCard: View {
    let item: DesktopTaskItem
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    DesktopAgentBadge(provider: item.provider, size: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(TaskDisplayTitle.compact(item.title))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DesktopTheme.ink)
                            .lineLimit(1)
                        Text(metadata)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DesktopTheme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 5) {
                        Circle().fill(item.stateColor).frame(width: 7, height: 7)
                        Text(item.stateLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(item.stateColor)
                    }
                }
                if let lastActive = item.lastActive {
                    Text("\(item.hasOpenExecution ? "Last active" : "Last update") \(lastActive)")
                        .font(.system(size: 11))
                        .foregroundStyle(DesktopTheme.muted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesktopTheme.raised,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DesktopTheme.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("task.row.\(item.taskId)")
    }

    private var metadata: String {
        [item.projectName, item.provider?.capitalized ?? "Agent"]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

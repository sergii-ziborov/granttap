import SwiftUI

struct TaskListCard: View {
    let item: TaskListItem
    var route: ChatComputerRoute? = nil

    var isPaused: Bool { item.currentSession?.isPaused == true }

    var presence: TaskPresence {
        if let route, route.phase != .live { return .offline }
        if isPaused { return .waiting }
        switch item.state {
        case "working": return item.hasOpenExecution ? .working : .idle
        case "blocked", "needs_user", "waiting": return .waiting
        default: return .idle
        }
    }

    var stateLabel: String {
        switch presence {
        case .offline: return L("Offline")
        case .working: return L("Working")
        case .waiting:
            if isPaused { return L("Paused") }
            return item.state == "blocked" ? L("Blocked") : L("Waiting")
        case .idle:
            if item.state == "failed" { return L("Failed") }
            return ["completed", "finished"].contains(item.state) ? L("Finished") : L("Idle")
        }
    }

    private var stateColor: Color {
        switch presence {
        case .working: return Theme.ok
        case .waiting: return Theme.riskMed
        case .offline, .idle: return Theme.muted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                AgentGlyph(agent: item.ownerProvider, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    Text(metadata)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    Circle().fill(stateColor).frame(width: 7, height: 7)
                    Text(stateLabel).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(stateColor)
                }
            }
            HStack(spacing: 8) {
                Text(item.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                     ? item.summary! : item.projectName)
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer(minLength: 4)
                if let percent = contextPercent, percent >= 65 {
                    Text("\(L("Context")) \(percent)%")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(percent >= 85 ? Theme.riskMed : Theme.muted)
                }
            }
            // When the task last did anything, so a quiet card is readable as
            // quiet rather than mistaken for live work.
            Text("\(L("Last active")) \(ConnectionLoadFormat.age(seconds: item.idleSeconds()))")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.muted)
                .accessibilityIdentifier("task.lastActive")
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line))
    }

    private var metadata: String {
        [item.projectName, item.ownerName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var contextPercent: Int? {
        guard let used = item.currentSession?.contextTokensUsed,
              let window = item.currentSession?.contextWindow, window > 0 else { return nil }
        return Int((Double(used) / Double(window) * 100).rounded())
    }
}

import SwiftUI

/// The controls above and behind a chat: pause and resume, a hand-off, a
/// report, and the strip that says what the chat is doing now.
extension TaskChatView {
    /// Pause, resume, move, report, settings: what a person does to a chat
    /// rather than in it, behind one button.
    var taskControlsMenu: some View {
        Menu {
            if currentSession.isPaused {
                Button {
                    model.resumeSession(chatSessionId)
                } label: {
                    Label(L("Resume and continue"), systemImage: "play.fill")
                }
                .disabled(controlPending)
            } else {
                Button {
                    model.pauseSession(chatSessionId)
                } label: {
                    Label(L("Pause"), systemImage: "pause.fill")
                }
                .disabled(controlPending)
            }
            if canHandOff {
                Button {
                    showHandoff = true
                } label: {
                    Label(L("Hand off to another agent or computer…"), systemImage: "arrow.right.arrow.left")
                }
            }
            Button {
                showReport = true
            } label: {
                Label(L("Report (PDF or CSV)…"), systemImage: "doc.text")
            }
            Divider()
            Button {
                showCapabilities = true
            } label: {
                Label(L("Task controls"), systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: currentSession.isPaused ? "pause.circle.fill" : "ellipsis.circle")
                .foregroundStyle(currentSession.isPaused ? Theme.riskMed : accent)
        }
        .accessibilityLabel(L("Task controls"))
        .accessibilityIdentifier("chat.menu")
    }

    var controlPending: Bool { model.sessionControlPending.contains(chatSessionId) }

    /// A Task inside a Project can move: to another agent here, or to another
    /// computer of the Project.
    var canHandOff: Bool {
        currentSession.projectId != nil && currentSession.taskId != nil
            && ["claude", "codex"].contains(AgentIdentity.normalize(currentSession.agent))
            && !model.connectionRegistry.connections.isEmpty
    }

    /// The report is about the Task when the chat belongs to one, so the other
    /// executions of the same Task are counted; otherwise about this chat alone.
    var reportScope: ReportScope {
        if let projectId = currentSession.projectId, let taskId = currentSession.taskId,
           let snapshot = model.meshSnapshots[projectId],
           let task = snapshot.tasks.first(where: { $0.taskId == taskId }) {
            return .task(snapshot, task)
        }
        return .chat(currentSession)
    }

    var taskStatusStrip: some View {
        HStack(spacing: 8) {
            AgentGlyph(agent: currentSession.agent, size: 18)
            Text([AgentIdentity.shortName(currentSession.agent), currentSession.model]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            if let route = model.chatComputerRoute(forSessionId: chatSessionId) {
                Text("· \(route.computerName)").lineLimit(1)
            }
            if currentSession.isPaused {
                Text(controlPending ? L("Pausing…") : L("Paused"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.riskMed)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.riskMed.opacity(0.14), in: Capsule())
                    .accessibilityIdentifier("chat.paused")
            } else if controlPending {
                Text(L("Resuming…")).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            if let percent = contextPercent {
                Text("\(L("Context")) \(percent)%")
                    .foregroundStyle(percent >= 85 ? Theme.riskMed : Theme.muted)
                if percent >= 85, AgentIdentity.normalize(currentSession.agent) == "codex" {
                    Button(L("Compact")) { model.compactSession(chatSessionId) }
                        .disabled(currentSession.state == "working" ||
                                  model.compactingSessions.contains(chatSessionId))
                }
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 16)
        .frame(minHeight: 36)
        .background(Theme.surface.opacity(0.96))
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }

    /// How full the chat's context window is, as the strip reports it.
    var contextPercent: Int? {
        guard let used = currentSession.contextTokensUsed,
              let window = currentSession.contextWindow, window > 0 else { return nil }
        return Int((Double(used) / Double(window) * 100).rounded())
    }
}

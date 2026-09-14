import SwiftUI

/// One execution of a Task as a row: when it ran, what state it is in, and
/// the chat it opens.
extension TaskRouteView {
    /// "Started 6 Sep 01:12 · last active 2 h ago · ended 6 Sep 03:40": when
    /// the execution ran, in the words of the list it came from.
    static func timingLine(_ execution: ExecutionSessionLink, now: Double = Date().timeIntervalSince1970 * 1_000) -> String {
        var parts = [String(format: L("started %@"), ReportBuilder.stamp(execution.startedAt))]
        if let endedAt = execution.endedAt {
            parts.append(String(format: L("ended %@"), ReportBuilder.stamp(endedAt)))
        } else {
            let seconds = Int(max(0, (now - execution.lastSeenAt) / 1_000))
            parts.append("\(L("last active")) \(ConnectionLoadFormat.age(seconds: seconds))")
        }
        return parts.joined(separator: " · ")
    }

    /// The same words the Task list uses for this state, not the raw value.
    var stateLine: String {
        let state = task.map { task in
            ProjectMeshTaskPresentation.label(ProjectMeshTaskPresentation.state(
                task: task, execution: ownerExecution, currentSession: localSession
            ))
        }
        let owner = ownerExecution.map(MeshActorPresentation.executionName)
        return [state, owner].compactMap { $0 }.joined(separator: " · ")
    }

    var visibleTitle: String {
        task.map { ProjectMeshTaskTitle.text($0, session: localSession) }
            ?? localSession.flatMap { ProjectMeshTaskTitle.presentable($0.displayTitle) }
            ?? route.taskId
    }

    @ViewBuilder
    func executionRow(_ execution: ExecutionSessionLink) -> some View {
        if session(for: execution) != nil {
            Button {
                dismiss()
                openChat(for: execution)
            } label: {
                executionContent(execution, chatAvailable: true)
            }
            .buttonStyle(.plain)
        } else {
            executionContent(execution, chatAvailable: false)
        }
    }

    func executionContent(
        _ execution: ExecutionSessionLink, chatAvailable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(MeshActorPresentation.executionName(execution))
                .font(.system(size: 14, weight: .semibold))
            // The computer is already in the name above; the line under it
            // says only what the name does not.
            let detail = [execution.branch, execution.endedAt == nil ? nil : L("Ended")]
                .compactMap { $0 }.joined(separator: " · ")
            if !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
            Text(Self.timingLine(execution)).font(.caption2).foregroundStyle(Theme.muted)
            if execution.endedAt == nil, execution.uncommitted != false {
                Text(L(execution.uncommitted == true
                       ? TaskHandoffReadiness.uncommittedReason
                       : TaskHandoffReadiness.unreadableWorkingTreeReason))
                    .font(.caption).foregroundStyle(Theme.riskHigh)
            }
            if chatAvailable {
                Label(L("Open chat"), systemImage: "bubble.left.and.bubble.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.codex)
            } else {
                Text(L("Chat is not retained on this iPhone."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder
    func answerSection(_ question: ProjectMeshEvent) -> some View {
        Section(L("Answer")) {
            Text(question.payload.question ?? "")
                .font(.system(size: 14, weight: .semibold))
            TextField(L("Your answer"), text: $answerText)
            Button(L("Send answer")) {
                model.answerMeshQuestion(question.eventId, text: answerText)
                answerText = ""
            }
            .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
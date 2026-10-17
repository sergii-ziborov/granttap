import SwiftUI

extension TaskHandoffSheet {
    var previousHandoffEvents: Set<String> {
        Set((session.projectId.flatMap { model.meshSnapshots[$0] }?.events ?? []).map(\.eventId))
    }

    /// Socket submission is not confirmation that a destination chat exists.
    func waitForHandoff(previousEvents: Set<String>, computer: String) async {
        if let cloud = cloudTarget {
            await waitForCloudRun(cloud, previousEvents: previousEvents, computer: computer)
            return
        }
        awaitingConfirmation = true
        pendingHandoffEvents = previousEvents
        pendingHandoffComputer = computer
        let outcome = await TaskHandoffConfirmationPoller.wait(lookup: {
            if let handoffError { return .failed(handoffError) }
            return TaskHandoffOutcome.observe(session: session,
                snapshot: session.projectId.flatMap { model.meshSnapshots[$0] },
                provider: AgentIdentity.normalize(targetProvider), computer: computer,
                previousEvents: previousEvents, notBefore: handoffNotBefore)
        }, destinationAvailable: { destination in
            (model.sessions + model.sessionHistory).contains { $0.sessionId == destination }
        }, observing: { observesHandoff })
        guard let outcome else { awaitingConfirmation = false; return }
        switch outcome {
        case .prepared(let destination):
            awaitingConfirmation = false
            // The first message carries the chosen model and effort, so an
            // agent-wide default cannot replace what was picked here.
            model.rememberTransferChoice(destination: destination, model: targetModel, effort: targetEffort)
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if let onPrepared { onPrepared(destination) }
                else { model.sessionToOpen = destination }
            }
        case .failed(let reason):
            handoffError = reason
            awaitingConfirmation = false
        case .waiting:
            // A missing reply must not offer another preparation.
            handoffError = L("Waiting for computer confirmation…")
        }
    }

    /// A cloud run is confirmed by the external execution the computer
    /// records, and shown as a link; nothing opens a chat for it.
    func waitForCloudRun(_ cloud: TaskHandoffCloudTarget, previousEvents: Set<String>, computer: String) async {
        awaitingConfirmation = true
        pendingHandoffEvents = previousEvents
        pendingHandoffComputer = computer
        let outcome = await CloudHandoffOutcome.wait(lookup: {
            if let handoffError { return .failed(handoffError) }
            return CloudHandoffOutcome.observe(session: session,
                snapshot: session.projectId.flatMap { model.meshSnapshots[$0] }, target: cloud,
                computer: computer, previousEvents: previousEvents, notBefore: handoffNotBefore)
        }, observing: { observesHandoff })
        switch outcome {
        case .started(let run)?:
            awaitingConfirmation = false
            cloudRun = run
        case .failed(let reason)?:
            awaitingConfirmation = false
            handoffError = reason
        case .waiting?:
            handoffError = L("Waiting for computer confirmation…")
        case nil:
            awaitingConfirmation = false
        }
    }

    func checkHandoffConfirmation() {
        guard let previous = pendingHandoffEvents, let computer = pendingHandoffComputer else { return }
        handoffError = nil
        submitting = true
        Task {
            await waitForHandoff(previousEvents: previous, computer: computer)
            submitting = false
        }
    }
}

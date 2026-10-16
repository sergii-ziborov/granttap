import SwiftUI

extension TaskHandoffSheet {
    var previousHandoffEvents: Set<String> {
        Set((session.projectId.flatMap { model.meshSnapshots[$0] }?.events ?? []).map(\.eventId))
    }

    /// Socket submission is not confirmation that a destination chat exists.
    func waitForHandoff(previousEvents: Set<String>, computer: String) async {
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

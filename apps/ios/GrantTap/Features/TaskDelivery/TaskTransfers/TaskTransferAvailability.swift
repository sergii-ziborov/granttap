import Foundation

enum TaskTransferAvailability {
    static func canOffer(for session: SessionInfo, linkedComputer: Bool, localComputer: Bool) -> Bool {
        guard let project = session.projectId, !project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let task = session.taskId, !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              AgentIdentity.composeIds.contains(AgentIdentity.normalize(session.agent)) else { return false }
        return linkedComputer || localComputer
    }
}

extension AppModel {
    func canOfferTaskTransfer(for session: SessionInfo) -> Bool {
        TaskTransferAvailability.canOffer(for: session,
            linkedComputer: !connectionRegistry.connections.isEmpty, localComputer: usesLocalTransferComputer)
    }
}

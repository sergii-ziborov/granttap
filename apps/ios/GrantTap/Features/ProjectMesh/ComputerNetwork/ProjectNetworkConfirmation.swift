import Foundation

struct ProjectNetworkConfirmation {
    var plan: ProjectNetworkPlan
    private(set) var rejected = Set<String>()

    var isConfirmed: Bool {
        rejected.isEmpty && plan.confirmedEndpoints == Set(plan.endpoints.map(\.id))
    }

    mutating func receive(_ ack: ProjectTransportAck, room: String) -> Bool {
        guard ack.type == "project.transport.ack", ack.projectId == plan.projectId,
              ack.sessionId == plan.projectId, ack.revision == plan.revision,
              ack.generatedAt.isFinite, ack.generatedAt >= 0,
              let endpoint = plan.endpoints.first(where: { $0.room == room && $0.id == ack.targetEndpointId }),
              let command = plan.commands.first(where: { $0.targetEndpointId == endpoint.id }),
              command.requestId == ack.requestId else { return false }
        if ack.accepted { plan.confirmedEndpoints.insert(endpoint.id) }
        else { rejected.insert(endpoint.id); plan.confirmedEndpoints.remove(endpoint.id) }
        return true
    }
}

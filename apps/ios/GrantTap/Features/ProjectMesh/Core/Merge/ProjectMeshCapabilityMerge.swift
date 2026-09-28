import Foundation

enum ProjectMeshCapabilityMerge {
    static func merge(
        into merged: inout ProjectMeshSnapshot,
        current: ProjectMeshSnapshot, incoming: ProjectMeshSnapshot
    ) {
        merged.skills = skills(
            current.skills, incoming.skills, publisher: incoming.publisherEndpointId
        )
        merged.mcpServers = servers(
            current.mcpServers, incoming.mcpServers, publisher: incoming.publisherEndpointId
        )
        var requests: [String: ProjectCapabilityRequest] = [:]
        for request in (current.capabilityRequests ?? []) + (incoming.capabilityRequests ?? []) {
            if let held = requests[request.id], held.requestedAt > request.requestedAt { continue }
            requests[request.id] = request
        }
        let sorted = requests.values.sorted { $0.id < $1.id }
        merged.capabilityRequests = sorted.isEmpty ? nil : sorted
        merged.capabilityObservations = observations(
            current.capabilityObservations, incoming.capabilityObservations,
            publisher: incoming.publisherEndpointId
        )
    }

    static func skills(
        _ current: [ProjectSharedSkill]?, _ incoming: [ProjectSharedSkill]?,
        publisher: String?
    ) -> [ProjectSharedSkill]? {
        let kept = (current ?? []).filter { publisher == nil || $0.endpointId != publisher }
        var byID: [String: ProjectSharedSkill] = [:]
        for skill in kept + (incoming ?? []) { byID[skill.id] = skill }
        let merged = byID.values.sorted { $0.id < $1.id }
        return merged.isEmpty ? nil : merged
    }

    static func observations(
        _ current: [ProjectCapabilityObservation]?, _ incoming: [ProjectCapabilityObservation]?,
        publisher: String?
    ) -> [ProjectCapabilityObservation]? {
        var byID: [String: ProjectCapabilityObservation] = [:]
        let kept = (current ?? []).filter { publisher == nil || $0.endpointId != publisher }
        for observation in kept + (incoming ?? []) {
            if let held = byID[observation.id], held.observedAt > observation.observedAt { continue }
            byID[observation.id] = observation
        }
        let merged = byID.values.sorted { $0.id < $1.id }
        return merged.isEmpty ? nil : merged
    }

    static func servers(
        _ current: [ProjectMcpServer]?, _ incoming: [ProjectMcpServer]?,
        publisher: String? = nil
    ) -> [ProjectMcpServer]? {
        var byID: [String: ProjectMcpServer] = [:]
        let kept = (current ?? []).filter { publisher == nil || $0.endpointId != publisher }
        for server in kept + (incoming ?? []) { byID[server.id] = server }
        let merged = byID.values.sorted { $0.id < $1.id }
        return merged.isEmpty ? nil : merged
    }
}

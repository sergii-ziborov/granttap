import Foundation

enum ProjectCapabilityUsage {
    static func events(
        _ all: [CapabilityUsageEvent], snapshot: ProjectMeshSnapshot,
        rooms: [String: String], kind: CapabilityUsageKind, name: String,
        endpointId: String? = nil, provider: String? = nil
    ) -> [CapabilityUsageEvent] {
        ProjectUsageStats.events(all, snapshot: snapshot, roomByEndpointId: rooms,
                                 endpointId: endpointId).filter {
            $0.kind == kind && $0.name == name && (provider == nil || $0.agent == provider)
        }
    }
}

struct ProjectCapabilityInfo {
    struct Field: Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }
    let name: String
    let title: String
    let kind: CapabilityUsageKind
    let endpointId: String?
    let provider: String?
    let description: String?
    let fields: [Field]

    static func skill(_ skill: ProjectSharedSkill) -> ProjectCapabilityInfo {
        var fields: [Field] = [.init(title: L("Scope"), value: L("Mesh skill bundle"))]
        if let value = skill.version { fields.append(.init(title: L("Version"), value: value)) }
        if let value = skill.state { fields.append(.init(title: L("State"), value: value)) }
        if let value = skill.source { fields.append(.init(title: L("Source"), value: value)) }
        if let value = skill.digest { fields.append(.init(title: L("Bundle digest"), value: value)) }
        return .init(name: skill.name, title: skill.name, kind: .skill,
                     endpointId: skill.endpointId, provider: nil,
                     description: skill.description, fields: fields)
    }

    static func server(_ server: ProjectMcpServer) -> ProjectCapabilityInfo {
        var fields: [Field] = [
            .init(title: L("Native configuration"),
                  value: L(server.configuredEnabled ? "Enabled" : "Disabled")),
            .init(title: L("Version"), value: server.version ?? L("Not reported")),
            .init(title: L("Reported executions"), value: "\(server.sessionIds.count)"),
        ]
        if let value = server.configDigest { fields.append(.init(title: L("Config digest"), value: value)) }
        if let value = server.authStatus { fields.append(.init(title: L("Authentication"), value: value)) }
        return .init(name: server.name, title: server.title ?? server.name, kind: .mcp,
                     endpointId: server.endpointId, provider: server.provider,
                     description: nil, fields: fields)
    }
}

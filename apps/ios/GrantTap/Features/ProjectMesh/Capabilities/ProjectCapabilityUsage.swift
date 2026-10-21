import Foundation

enum ProjectCapabilityUsage {
    static func observedSkills(_ all: [String: [CapabilityExecutionSummary]], snapshot: ProjectMeshSnapshot,
                               rooms: [String: String]) -> [ProjectCapabilityInfo] {
        var rows: [String: ProjectCapabilityInfo] = [:]
        for execution in snapshot.executions {
            guard let room = rooms[execution.computerId] else { continue }
            for report in all[room] ?? [] where report.kind == .skill && report.count > 0
                && report.agent == execution.provider && report.sessionId == execution.sessionId {
                if snapshot.skills?.contains(where: {
                    $0.name == report.name && $0.endpointId == execution.computerId
                }) == true { continue }
                let info = ProjectCapabilityInfo(name: report.name, title: report.name, kind: .skill,
                    endpointId: execution.computerId, provider: report.agent, description: L("Observed skill"),
                    fields: [.init(title: L("Scope"), value: L("Observed in this Project"))])
                rows[info.id] = info
            }
        }
        return rows.values.sorted { $0.id < $1.id }
    }
    static func recorded(_ all: [String: [CapabilityExecutionSummary]], snapshot: ProjectMeshSnapshot,
                         rooms: [String: String], info: ProjectCapabilityInfo) -> ProjectRecordedUsage? {
        let keys = Set(snapshot.executions.compactMap { execution -> String? in
            guard info.endpointId == nil || execution.computerId == info.endpointId,
                  let room = rooms[execution.computerId] else { return nil }
            return [room, execution.provider, execution.sessionId].joined(separator: "\u{1f}")
        })
        let rows = all.flatMap { room, summaries in
            summaries.filter { row in
                row.kind == info.kind && (info.provider == nil || row.agent == info.provider)
                    && keys.contains([room, row.agent, row.sessionId].joined(separator: "\u{1f}"))
                    && matches(row.name, info: info, snapshot: snapshot)
            }
        }
        guard !rows.isEmpty else { return nil }
        let durations = rows.compactMap(\.durationMs).reduce(0, +)
        let samples = rows.compactMap(\.durationCount).reduce(0, +)
        return .init(count: rows.map(\.count).reduce(0, +),
                     failures: rows.map(\.failures).reduce(0, +),
                     lastUsedAt: rows.map(\.lastUsedAt).max() ?? 0,
                     averageDurationMs: samples > 0 ? durations / samples : nil)
    }
    static func events(
        _ all: [CapabilityUsageEvent], snapshot: ProjectMeshSnapshot,
        rooms: [String: String], kind: CapabilityUsageKind, name: String,
        endpointId: String? = nil, provider: String? = nil
    ) -> [CapabilityUsageEvent] {
        ProjectUsageStats.events(all, snapshot: snapshot, roomByEndpointId: rooms,
                                 endpointId: endpointId).filter {
            $0.kind == kind && matches($0.name, info: .init(name: name, title: name, kind: kind,
                endpointId: endpointId, provider: provider, description: nil, fields: []), snapshot: snapshot)
                && (provider == nil || $0.agent == provider)
        }
    }

    private static func matches(_ observed: String, info: ProjectCapabilityInfo,
                                snapshot: ProjectMeshSnapshot) -> Bool {
        if observed == info.name { return true }
        guard info.kind == .mcp else { return false }
        let normalize = { (value: String) in value.replacingOccurrences(of: "_", with: "-") }
        guard normalize(observed) == normalize(info.name) else { return false }
        let names = Set((snapshot.mcpServers ?? []).filter {
            (info.endpointId == nil || $0.endpointId == info.endpointId)
                && (info.provider == nil || $0.provider == info.provider)
                && normalize($0.name) == normalize(info.name)
        }.map(\.name))
        return names == [info.name]
    }
}

struct ProjectRecordedUsage {
    let count: Int
    let failures: Int
    let lastUsedAt: Double
    let averageDurationMs: Int?
}

struct ProjectCapabilityInfo: Identifiable {
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
    var id: String { [kind.rawValue, name, endpointId ?? "", provider ?? ""].joined(separator: "\u{1f}") }

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

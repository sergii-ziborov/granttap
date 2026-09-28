import SwiftUI

/// Point-in-time process measurements for exact active Project executions.
/// Historical CPU time still comes from invocation receipts; a process sample
/// must never be added to that total or labelled as a completed Task cost.
struct ProjectLiveComputerLoad: Identifiable, Equatable {
    let endpointId: String
    let cpuPercent: Double
    let memoryBytes: Double
    let processes: Int
    let sampledAt: Double

    var id: String { endpointId }
}

/// Provider process load on a host participating in this Project. It can
/// include work from other Projects and is never a Project cost estimate.
struct ProjectHostAgentLoad: Identifiable, Equatable {
    let endpointId: String
    let provider: String
    let cpuPercent: Double
    let memoryBytes: Double
    let processes: Int

    var id: String { "\(endpointId)\u{1f}\(provider)" }
}

enum ProjectLiveResources {
    static let maxAgeMs: Double = 120_000

    static func samples(
        snapshot: ProjectMeshSnapshot,
        roomByEndpointId: [String: String], loadsByRoom: [String: MachineLoad],
        nowMs: Double
    ) -> [ProjectLiveComputerLoad] {
        var grouped: [String: ProjectLiveComputerLoad] = [:]
        var seen = Set<String>()
        for execution in snapshot.executions where execution.endedAt == nil {
            guard seen.insert(execution.id).inserted,
                  let room = roomByEndpointId[execution.computerId],
                  let load = loadsByRoom[room],
                  fresh(load, at: nowMs),
                  let agent = load.agents.first(where: { $0.agent == execution.provider }),
                  let chat = agent.chats.first(where: { $0.sessionId == execution.sessionId }),
                  chat.cpuPercent.isFinite, chat.cpuPercent >= 0,
                  chat.memoryBytes.isFinite, chat.memoryBytes >= 0 else { continue }
            let prior = grouped[execution.computerId]
            grouped[execution.computerId] = ProjectLiveComputerLoad(
                endpointId: execution.computerId,
                cpuPercent: (prior?.cpuPercent ?? 0) + chat.cpuPercent,
                memoryBytes: (prior?.memoryBytes ?? 0) + chat.memoryBytes,
                processes: (prior?.processes ?? 0) + max(0, chat.processes),
                sampledAt: load.generatedAt
            )
        }
        return grouped.values.sorted { $0.endpointId < $1.endpointId }
    }

    static func hostSamples(
        snapshot: ProjectMeshSnapshot,
        roomByEndpointId: [String: String], loadsByRoom: [String: MachineLoad],
        nowMs: Double
    ) -> [ProjectHostAgentLoad] {
        var result: [String: ProjectHostAgentLoad] = [:]
        for execution in snapshot.executions where execution.endedAt == nil {
            guard let room = roomByEndpointId[execution.computerId],
                  let load = loadsByRoom[room], fresh(load, at: nowMs),
                  let agent = load.agents.first(where: { $0.agent == execution.provider }),
                  agent.cpuPercent.isFinite, agent.cpuPercent >= 0,
                  agent.memoryBytes.isFinite, agent.memoryBytes >= 0,
                  agent.processes > 0 else { continue }
            let sample = ProjectHostAgentLoad(
                endpointId: execution.computerId, provider: execution.provider,
                cpuPercent: agent.cpuPercent, memoryBytes: agent.memoryBytes,
                processes: agent.processes
            )
            result[sample.id] = sample
        }
        return result.values.sorted { $0.id < $1.id }
    }

    private static func fresh(_ load: MachineLoad, at nowMs: Double) -> Bool {
        load.generatedAt > 0 && load.generatedAt <= nowMs + 5_000
            && nowMs - load.generatedAt <= maxAgeMs
    }
}

struct ProjectLiveResourceRow: View {
    let sample: ProjectLiveComputerLoad
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
            Text(String(format: L("%.1f%% CPU · %@ RAM · %d processes"),
                        sample.cpuPercent,
                        CapabilityResourceFormat.bytes(Int(min(sample.memoryBytes, Double(Int.max)))),
                        sample.processes))
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

struct ProjectHostAgentResourceRow: View {
    let sample: ProjectHostAgentLoad
    let computerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(computerName) · \(sample.provider)")
            Text(String(format: L("%.1f%% CPU · %@ RAM · %d processes"),
                        sample.cpuPercent,
                        CapabilityResourceFormat.bytes(Int(min(sample.memoryBytes, Double(Int.max)))),
                        sample.processes))
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

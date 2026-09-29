import Foundation

/// The local MCP's process sample uses the same attribution rules as relay reports.
struct MacLocalMachineLoad: Decodable {
    struct Group: Decodable {
        let name: String
        let count: Int
        let cpu_percent: Double
        let memory_bytes: Double
    }
    struct Agent: Decodable, Identifiable {
        let agent: String
        let processes: Int
        let cpu_percent: Double
        let memory_bytes: Double
        let groups: [Group]
        var chats: [ChatProcessLoad]? = nil
        var id: String { agent }
    }
    let operation: String
    let source: String
    let computer: String
    let observed_at: Double
    let agents: [Agent]

    var isValid: Bool {
        operation == "desktop.machine_load" && source == "process_sample"
            && !computer.isEmpty && observed_at.isFinite && observed_at > 0 && agents.count <= 16
            && agents.allSatisfy { agent in
                !agent.agent.isEmpty && agent.processes >= 0
                    && valid(cpu: agent.cpu_percent, memory: agent.memory_bytes)
                    && agent.groups.count <= 8 && agent.groups.allSatisfy {
                        $0.count >= 0 && valid(cpu: $0.cpu_percent, memory: $0.memory_bytes)
                    }
                    && (agent.chats?.count ?? 0) <= 128 && (agent.chats?.allSatisfy {
                        !$0.sessionId.isEmpty && $0.processes >= 0
                            && valid(cpu: $0.cpuPercent, memory: $0.memoryBytes)
                    } ?? true)
            }
    }

    var wireLoad: MachineLoad {
        .init(machine: computer, monitorCpuPercent: 0, monitorMemoryBytes: 0,
              agents: agents.map { agent in
                  .init(agent: agent.agent, processes: agent.processes,
                        cpuPercent: agent.cpu_percent, memoryBytes: agent.memory_bytes,
                        topProcesses: agent.groups.map {
                            .init(name: $0.name, count: $0.count, cpuPercent: $0.cpu_percent,
                                  memoryBytes: $0.memory_bytes)
                        }, chats: agent.chats ?? [])
              }, generatedAt: observed_at)
    }

    private func valid(cpu: Double, memory: Double) -> Bool {
        cpu.isFinite && cpu >= 0 && memory.isFinite && memory >= 0
    }
}

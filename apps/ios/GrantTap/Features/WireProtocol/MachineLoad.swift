import Foundation

/// One kind of process an agent runs — `node` ×43, `zsh` ×10 — and what it costs.
struct ProcessGroupLoad: Codable, Identifiable, Equatable {
    let name: String
    let count: Int
    let cpuPercent: Double
    let memoryBytes: Double
    var id: String { name }
}

/// One process on its own: who, in the list a person opens, eats what.
struct ProcessLoadRow: Codable, Identifiable, Equatable {
    let pid: Int
    let name: String
    let cpuPercent: Double
    let memoryBytes: Double
    var detail: String? = nil
    var sessionId: String? = nil
    var id: Int { pid }
}

/// What one chat's processes cost together.
struct ChatProcessLoad: Codable, Identifiable, Equatable {
    let sessionId: String
    let processes: Int
    let cpuPercent: Double
    let memoryBytes: Double
    var id: String { sessionId }
}

struct DiskUsageEntry: Codable, Identifiable, Equatable {
    let path: String
    let bytes: Double
    var id: String { path }
}

/// What the agent keeps on the disk: its own folders, heaviest places first.
struct AgentDiskUsage: Codable, Equatable {
    let measuredAt: Double
    let totalBytes: Double
    let entries: [DiskUsageEntry]
}

/// One agent's measured share of what the computer is doing.
///
/// The families are deliberately not merged into a single "load" number: CPU
/// comes from that agent's own processes, `scanMs` is what GrantTap spends
/// reading its logs, and tokens are model spend. A machine can be hot from any
/// one of them while the others look idle.
struct AgentLoadSample: Decodable, Identifiable, Equatable {
    let agent: String
    let processes: Int
    let cpuPercent: Double
    let memoryBytes: Double
    let sessions: Int
    let scanMs: Double
    let tokensRecent: Double
    let contextTokens: Double?
    /// The heaviest kinds of process behind the number, heaviest first.
    let topProcesses: [ProcessGroupLoad]
    /// The heaviest processes one by one, and the same load by chat.
    let processList: [ProcessLoadRow]
    let chats: [ChatProcessLoad]
    let disk: AgentDiskUsage?

    var id: String { agent }

    enum CodingKeys: String, CodingKey {
        case agent, processes, cpuPercent, memoryBytes, sessions, scanMs
        case tokensRecent, contextTokens, topProcesses, processList, chats, disk
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agent = (try? c.decode(String.self, forKey: .agent)) ?? ""
        processes = (try? c.decode(Int.self, forKey: .processes)) ?? 0
        cpuPercent = (try? c.decode(Double.self, forKey: .cpuPercent)) ?? 0
        memoryBytes = (try? c.decode(Double.self, forKey: .memoryBytes)) ?? 0
        sessions = (try? c.decode(Int.self, forKey: .sessions)) ?? 0
        scanMs = (try? c.decode(Double.self, forKey: .scanMs)) ?? 0
        tokensRecent = (try? c.decode(Double.self, forKey: .tokensRecent)) ?? 0
        contextTokens = try? c.decode(Double.self, forKey: .contextTokens)
        topProcesses = (try? c.decode([ProcessGroupLoad].self, forKey: .topProcesses)) ?? []
        processList = (try? c.decode([ProcessLoadRow].self, forKey: .processList)) ?? []
        chats = (try? c.decode([ChatProcessLoad].self, forKey: .chats)) ?? []
        disk = try? c.decode(AgentDiskUsage.self, forKey: .disk)
    }

    init(agent: String, processes: Int = 0, cpuPercent: Double = 0,
         memoryBytes: Double = 0, sessions: Int = 0, scanMs: Double = 0,
         tokensRecent: Double = 0, contextTokens: Double? = nil,
         topProcesses: [ProcessGroupLoad] = [], processList: [ProcessLoadRow] = [],
         chats: [ChatProcessLoad] = [], disk: AgentDiskUsage? = nil) {
        self.agent = agent
        self.processes = processes
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.sessions = sessions
        self.scanMs = scanMs
        self.tokensRecent = tokensRecent
        self.contextTokens = contextTokens
        self.topProcesses = topProcesses
        self.processList = processList
        self.chats = chats
        self.disk = disk
    }
}

struct MachineLoad: Decodable, Equatable {
    let type: String
    let machine: String
    let monitorCpuPercent: Double
    let monitorMemoryBytes: Double
    let agents: [AgentLoadSample]
    let generatedAt: Double

    enum CodingKeys: String, CodingKey {
        case type, machine, monitorCpuPercent, monitorMemoryBytes, agents, generatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? "machine.load"
        machine = (try? c.decode(String.self, forKey: .machine)) ?? ""
        monitorCpuPercent = (try? c.decode(Double.self, forKey: .monitorCpuPercent)) ?? 0
        monitorMemoryBytes = (try? c.decode(Double.self, forKey: .monitorMemoryBytes)) ?? 0
        agents = (try? c.decode([AgentLoadSample].self, forKey: .agents)) ?? []
        generatedAt = (try? c.decode(Double.self, forKey: .generatedAt)) ?? 0
    }

    init(machine: String, monitorCpuPercent: Double, monitorMemoryBytes: Double,
         agents: [AgentLoadSample], generatedAt: Double) {
        self.type = "machine.load"
        self.machine = machine
        self.monitorCpuPercent = monitorCpuPercent
        self.monitorMemoryBytes = monitorMemoryBytes
        self.agents = agents
        self.generatedAt = generatedAt
    }

    /// Share of the measured agent CPU this agent accounts for, or nil when
    /// nothing is running — a zero denominator must not render as "0%" of a
    /// load the user can plainly see is there.
    func cpuShare(of sample: AgentLoadSample) -> Double? {
        let total = agents.reduce(0) { $0 + $1.cpuPercent }
        guard total > 0 else { return nil }
        return sample.cpuPercent / total
    }
}

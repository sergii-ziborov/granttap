import Foundation
import os

/// One reading of a computer's load, small enough to keep an hour of them.
///
/// The live number answers "what is it doing now"; an hour of readings answers
/// the question people actually bring to the screen — "what was it doing when
/// my phone got warm ten minutes ago" — and no single sample can.
struct LoadHistoryPoint: Codable, Equatable, Identifiable {
    struct Agent: Codable, Equatable {
        let agent: String
        let cpuPercent: Double
        let memoryBytes: Double
        let processes: Int
    }

    /// Epoch milliseconds, as the computer stamped it.
    let at: Double
    let monitorCpuPercent: Double
    let monitorMemoryBytes: Double
    let agents: [Agent]
    var id: Double { at }

    init(_ load: MachineLoad) {
        at = load.generatedAt
        monitorCpuPercent = load.monitorCpuPercent
        monitorMemoryBytes = load.monitorMemoryBytes
        agents = load.agents.map {
            Agent(agent: $0.agent, cpuPercent: $0.cpuPercent, memoryBytes: $0.memoryBytes, processes: $0.processes)
        }
    }

    init(at: Double, monitorCpuPercent: Double = 0, monitorMemoryBytes: Double = 0, agents: [Agent] = []) {
        self.at = at
        self.monitorCpuPercent = monitorCpuPercent
        self.monitorMemoryBytes = monitorMemoryBytes
        self.agents = agents
    }

    var agentCpuTotal: Double { agents.reduce(0) { $0 + $1.cpuPercent } }
    var agentMemoryTotal: Double { agents.reduce(0) { $0 + $1.memoryBytes } }
    func cpu(of agent: String) -> Double? { agents.first { $0.agent == agent }?.cpuPercent }
    func memory(of agent: String) -> Double? { agents.first { $0.agent == agent }?.memoryBytes }
    func processes(of agent: String) -> Int? { agents.first { $0.agent == agent }?.processes }
}

enum LoadHistory {
    static let windowMs: Double = 60 * 60 * 1_000
    /// A reading every five seconds for an hour; the computer reports far less often.
    static let maxPoints = 720

    /// The readings with one more, keeping the last hour and nothing older.
    static func appending(
        _ load: MachineLoad, to points: [LoadHistoryPoint], now: Double? = nil
    ) -> [LoadHistoryPoint] {
        let point = LoadHistoryPoint(load)
        let cutoff = (now ?? point.at) - windowMs
        // A reading that arrives late still belongs where its time puts it; a
        // reading with the same stamp replaces the earlier copy of itself.
        var next = points.filter { $0.at >= cutoff && $0.at != point.at }
        next.append(point)
        next.sort { $0.at < $1.at }
        if next.count > maxPoints { next.removeFirst(next.count - maxPoints) }
        return next
    }

    /// Evenly spaced slots for a chart, each holding the highest reading that
    /// fell into it — a spike is the thing worth seeing, not the thing to
    /// average away — and nil where nothing was reported.
    static func series(
        _ points: [LoadHistoryPoint], slots: Int, since: Double, until: Double,
        value: (LoadHistoryPoint) -> Double?
    ) -> [Double?] {
        guard slots > 0, until > since else { return [] }
        var out = [Double?](repeating: nil, count: slots)
        let width = (until - since) / Double(slots)
        for point in points where point.at >= since && point.at <= until {
            guard let reading = value(point) else { continue }
            let index = min(slots - 1, max(0, Int((point.at - since) / width)))
            out[index] = max(out[index] ?? 0, reading)
        }
        return out
    }
}

/// Which of two reports of one computer to believe.
enum LoadReportPolicy {
    /// How long a report that lists processes and chats outranks one that does not.
    static let richerWindowMs: Double = 60_000

    /// True when the report already held should stay: it lists what the agents
    /// run, the new one does not, and it is not yet a minute old. A reporter
    /// that has learned to list processes does not unlearn it; a report without
    /// them is another, older reporter on the same computer.
    static func supersedes(_ held: MachineLoad, over incoming: MachineLoad) -> Bool {
        let heldRich = held.agents.contains { !$0.processList.isEmpty || !$0.chats.isEmpty }
        let incomingRich = incoming.agents.contains { !$0.processList.isEmpty || !$0.chats.isEmpty }
        guard heldRich, !incomingRich else { return false }
        return incoming.generatedAt - held.generatedAt < richerWindowMs
    }
}

/// An hour of readings per computer, kept across launches so the chart is
/// not empty every time the app comes back.
enum LoadHistoryPersistence {
    private static let logger = Logger(subsystem: "com.ziborov.granttap", category: "persistence")
    /// Readings arrive every few seconds; the file is worth writing twice a minute.
    static let saveIntervalMs: Double = 30_000
    private static var lastSavedAt: [String: Double] = [:]
    private static var pending: [String: [LoadHistoryPoint]] = [:]
    private static let queue = DispatchQueue(label: "com.ziborov.granttap.load-history", qos: .utility)

    /// Write soon, not now: encoding seven hundred points on the main thread
    /// on every sample is what made every scrolling screen stutter.
    static func scheduleSave(_ points: [LoadHistoryPoint], room: String, now: Double = Date().timeIntervalSince1970 * 1_000) {
        pending[room] = points
        let last = lastSavedAt[room] ?? 0
        guard now - last >= saveIntervalMs else { return }
        lastSavedAt[room] = now
        let snapshot = points
        queue.async { save(snapshot, room: room) }
    }

    /// Whatever is still unsaved, written now — for the app going to the
    /// background. Waits for the queue, so a write scheduled a moment ago
    /// cannot land after this one and undo it.
    static func flush() {
        let batch = pending
        pending = [:]
        let now = Date().timeIntervalSince1970 * 1_000
        for (room, points) in batch {
            lastSavedAt[room] = now
            queue.async { save(points, room: room) }
        }
        queue.sync {}
    }

    static func load(room: String) -> [LoadHistoryPoint] {
        guard let data = try? Data(contentsOf: fileURL(room)),
              let points = try? JSONDecoder().decode([LoadHistoryPoint].self, from: data) else { return [] }
        let cutoff = Date().timeIntervalSince1970 * 1_000 - LoadHistory.windowMs
        return points.filter { $0.at >= cutoff }
    }

    static func save(_ points: [LoadHistoryPoint], room: String) {
        guard let data = try? JSONEncoder().encode(points) else { return }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: fileURL(room), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Load-history write failed (code: \((error as NSError).code, privacy: .public))")
        }
    }

    static func remove(room: String) { try? FileManager.default.removeItem(at: fileURL(room)) }

    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrantTap", isDirectory: true)
    }

    private static func fileURL(_ room: String) -> URL {
        let safe = room.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return directoryURL.appendingPathComponent("load-history-\(safe.prefix(64)).json")
    }
}

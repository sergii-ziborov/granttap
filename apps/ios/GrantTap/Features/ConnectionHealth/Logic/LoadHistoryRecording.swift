import Foundation

extension AppModel {
    /// A reading is the live number and one more point of the hour behind it.
    func recordMachineLoad(_ load: MachineLoad, fromRoom room: String) {
        // Two reporters on one computer — the monitor and an MCP server that
        // started with last week's code — made the numbers flicker. A report
        // that knows less than the one a minute ago is the older reporter.
        if let held = machineLoadByRoom[room], LoadReportPolicy.supersedes(held, over: load) { return }
        machineLoadByRoom[room] = load
        let history = machineLoadHistoryByRoom[room] ?? LoadHistoryPersistence.load(room: room)
        let next = LoadHistory.appending(load, to: history)
        machineLoadHistoryByRoom[room] = next
        LoadHistoryPersistence.scheduleSave(next, room: room)
    }

    /// The hour behind a computer, read back from disk on first use.
    func loadHistory(room: String) -> [LoadHistoryPoint] {
        if let held = machineLoadHistoryByRoom[room] { return held }
        let stored = LoadHistoryPersistence.load(room: room)
        if !stored.isEmpty { machineLoadHistoryByRoom[room] = stored }
        return stored
    }
}

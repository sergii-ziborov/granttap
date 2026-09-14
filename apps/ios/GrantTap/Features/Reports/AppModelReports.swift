import Foundation

extension AppModel {
    /// Everything the phone holds about a scope, assembled once.
    func report(for scope: ReportScope, now: Date = Date()) -> ProjectReport {
        ReportBuilder.build(scope, inputs: reportInputs(now: now))
    }

    func reportInputs(now: Date = Date()) -> ReportInputs {
        var inputs = ReportInputs()
        inputs.now = now
        inputs.sessions = sessions + allSessionHistory + Array(archivedSessions.values)
        inputs.events = CapabilityUsageStore.shared.events
        inputs.meshEvents = meshSnapshots.values.flatMap(\.events) + pendingMeshEvents
        // Load is kept by pairing room; a computer in the mesh is known by the
        // name it publishes, so the two are joined here through the pairing.
        var history: [String: [LoadHistoryPoint]] = [:]
        var latest: [String: MachineLoad] = [:]
        for connection in connectionRegistry.connections {
            let name = ReportBuilder.computerKey(connection)
            if let points = machineLoadHistoryByRoom[connection.id], !points.isEmpty {
                history[name, default: []].append(contentsOf: points)
            }
            if let load = machineLoadByRoom[connection.id] { latest[name] = load }
        }
        inputs.loadHistory = history.mapValues { $0.sorted { $0.at < $1.at } }
        inputs.latestLoad = latest
        let names = Dictionary(connectionRegistry.connections.map { (ReportBuilder.computerKey($0), $0.displayName) },
                               uniquingKeysWith: { first, _ in first })
        inputs.computerName = { endpoint in names[endpoint] ?? endpoint }
        let preferences = projectPreferences
        inputs.projectName = { snapshot in ProjectsCatalog.displayName(snapshot, preference: preferences[snapshot.projectId]) }
        return inputs
    }
}

extension ReportBuilder {
    /// The name a computer publishes into the mesh, which is what executions
    /// carry; the pairing's own label is what the person sees.
    static func computerKey(_ connection: LinkedComputer) -> String {
        let published = connection.lastMachineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return published.isEmpty ? connection.id : published
    }
}

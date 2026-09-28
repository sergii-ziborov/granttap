#if targetEnvironment(macCatalyst)
import Foundation

private struct MacLocalUsageEnvelope: Decodable {
    let operation: String
    let type: String
    let events: [RemoteCapabilityUsageEvent]
    let totals: [CapabilityUsageTotal]?
    let generatedAt: Double
    let sessions: [SessionUsageSnapshot]?
}

struct MacLocalUsageSnapshot {
    let status: CapabilityUsageStatus
    let sessions: [SessionUsageSnapshot]
}

extension MacLocalMCPClient {
    static func usage(socketPath: String) async throws -> MacLocalUsageSnapshot {
        let data = try await read(socketPath: socketPath,
                                  operation: "desktop.capability_usage", input: nil)
        let envelope = try JSONDecoder().decode(MacLocalUsageEnvelope.self, from: data)
        guard envelope.operation == "desktop.capability_usage",
              envelope.type == "capability.usage.status",
              envelope.events.count <= 1_000,
              (envelope.totals?.count ?? 0) <= 256,
              (envelope.sessions?.count ?? 0) <= 512,
              envelope.sessions?.allSatisfy(\.isValid) ?? true,
              envelope.generatedAt.isFinite else { throw MacLocalMCPError.incompatible }
        return MacLocalUsageSnapshot(status: CapabilityUsageStatus(
            type: envelope.type, events: envelope.events,
            totals: envelope.totals, generatedAt: envelope.generatedAt),
            sessions: envelope.sessions ?? [])
    }
}
#endif

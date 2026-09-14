import Foundation

struct CapabilityCatalogEntry: Codable, Equatable {
    let provider: String
    var workspace: String?
    let kind: CapabilityUsageKind
    let name: String
    let available: Bool
    var allowed: Bool
}

struct CapabilityCatalogStatus: Codable, Equatable {
    let type: String
    /// Informational only. The authenticated RelayClient room is authoritative.
    let computerId: String
    let machine: String
    let entries: [CapabilityCatalogEntry]
    let generatedAt: Double
}

struct CapabilityCatalogRow: Identifiable, Equatable {
    let roomId: String
    let machine: String
    let provider: String
    let workspace: String?
    let kind: CapabilityUsageKind
    let name: String
    let available: Bool
    var allowed: Bool

    var id: String {
        [roomId, provider, workspace ?? "", kind.rawValue, name].joined(separator: "\u{0}")
    }
}

@MainActor
final class CapabilityCatalogStore: ObservableObject {
    static let shared = CapabilityCatalogStore()
    @Published private(set) var rows: [CapabilityCatalogRow] = []

    func apply(_ status: CapabilityCatalogStatus, fromRoom roomId: String) {
        let incoming = status.entries.map { entry in
            CapabilityCatalogRow(
                roomId: roomId,
                machine: status.machine,
                provider: AgentIdentity.normalize(entry.provider),
                workspace: entry.workspace,
                kind: entry.kind,
                name: entry.name,
                available: entry.available,
                allowed: entry.allowed
            )
        }
        rows = (rows.filter { $0.roomId != roomId } + incoming).sorted {
            ($0.machine, $0.provider, $0.workspace ?? "", $0.kind.rawValue, $0.name)
                < ($1.machine, $1.provider, $1.workspace ?? "", $1.kind.rawValue, $1.name)
        }
    }

    func setAllowed(_ allowed: Bool, kind: CapabilityUsageKind,
                    name: String, roomId: String) {
        rows = rows.map { row in
            guard row.roomId == roomId, row.kind == kind, row.name == name else { return row }
            var next = row
            next.allowed = allowed
            return next
        }
    }
}

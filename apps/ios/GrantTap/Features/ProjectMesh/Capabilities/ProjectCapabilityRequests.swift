import Foundation

struct ProjectCapabilityRequest: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case skill, mcp
        var id: String { rawValue }
        var title: String { self == .skill ? L("Skill") : L("MCP server") }
    }

    let projectId: String
    var requestId: String? = nil
    let kind: Kind
    let name: String
    var source: String? = nil
    var version: String? = nil
    var artifactDigest: String? = nil
    var targetEndpointId: String? = nil
    let requestedAt: Double
    var id: String {
        "\(projectId)\u{1f}\(kind.rawValue)\u{1f}\(name.lowercased())\u{1f}\(targetEndpointId ?? "")"
    }
}

struct ProjectCapabilityObservation: Codable, Equatable, Identifiable {
    let projectId: String
    let requestId: String
    let endpointId: String
    let state: String
    var version: String? = nil
    var artifactDigest: String? = nil
    let observedAt: Double
    var id: String { "\(requestId)\u{1f}\(endpointId)" }
}

struct ProjectCapabilityRequestSet: Codable {
    let type: String
    let sessionId: String
    let requestId: String
    let projectId: String
    let kind: ProjectCapabilityRequest.Kind
    let name: String
    var source: String? = nil
    var version: String? = nil
    var artifactDigest: String? = nil
    var targetEndpointId: String? = nil
    let requestedAt: Double

    var isWellFormed: Bool {
        let age = Date().timeIntervalSince1970 * 1_000 - requestedAt
        return type == "project.capability.request" && sessionId == projectId
            && !projectId.isEmpty && projectId.count <= 128
            && !requestId.isEmpty && requestId.count <= 128
            && !name.isEmpty && name.count <= 160
            && (source?.count ?? 0) <= 512 && (version?.count ?? 0) <= 128
            && (targetEndpointId?.count ?? 0) <= 128
            && (artifactDigest.map { digest in
                digest.utf8.count == 64 && digest.utf8.allSatisfy {
                    (48...57).contains($0) || (97...102).contains($0)
                }
            } ?? true)
            && requestedAt.isFinite && age <= 24 * 60 * 60 * 1_000
            && age >= -5 * 60 * 1_000
    }
}

enum ProjectCapabilityRequestStore {
    private static let key = "granttap.project-capability-requests.v1"

    static func load() -> [String: [ProjectCapabilityRequest]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(
                [String: [ProjectCapabilityRequest]].self, from: data
              ) else { return [:] }
        return decoded
    }

    static func save(_ values: [String: [ProjectCapabilityRequest]]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@MainActor
extension AppModel {
    func registerCapabilitySource(snapshot: ProjectMeshSnapshot, room: String) -> Bool {
        let newRoom = meshProjectSourceRooms[snapshot.projectId]?.contains(room) != true
        meshProjectSourceRooms[snapshot.projectId, default: []].insert(room)
        // Bindings and library reports can describe other computers. Only the
        // snapshot publisher is evidence for this room's delivery route.
        if let endpointId = snapshot.publisherEndpointId {
            meshComputerRoomByEndpointId[endpointId] = room
        }
        return newRoom
    }

    func requestProjectCapability(
        projectId: String, kind: ProjectCapabilityRequest.Kind,
        name: String, source: String?, version: String?,
        artifactDigest: String? = nil, targetEndpointId: String? = nil
    ) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard meshSnapshots[projectId] != nil, !clean.isEmpty, clean.count <= 160,
              (source?.count ?? 0) <= 512, (version?.count ?? 0) <= 128,
              artifactDigest == nil || artifactDigest?.count == 64 else { return }
        let request = ProjectCapabilityRequest(
            projectId: projectId, requestId: UUID().uuidString.lowercased(),
            kind: kind, name: clean,
            source: source?.nilIfBlank, version: version?.nilIfBlank,
            artifactDigest: artifactDigest, targetEndpointId: targetEndpointId,
            requestedAt: Date().timeIntervalSince1970 * 1_000
        )
        var rows = requestedProjectCapabilities[projectId] ?? []
        rows.removeAll { $0.kind == kind && $0.name.caseInsensitiveCompare(clean) == .orderedSame
            && $0.targetEndpointId == targetEndpointId }
        rows.append(request)
        requestedProjectCapabilities[projectId] = Array(rows.suffix(128))
        flushProjectCapabilityRequests(projectId: projectId)
    }

    /// Resend a durable request after reconnect until that endpoint reports a
    /// result. The request ID is stable, so relay retries cannot create a
    /// second Project manifest entry.
    func flushProjectCapabilityRequests(projectId: String? = nil) {
        let now = Date().timeIntervalSince1970 * 1_000
        let ids = projectId.map { [$0] } ?? Array(requestedProjectCapabilities.keys)
        for id in ids {
            let rooms = meshProjectSourceRooms[id] ?? []
            let observed = meshSnapshots[id]?.capabilityObservations ?? []
            for request in requestedProjectCapabilities[id] ?? [] {
                guard let requestId = request.requestId,
                      now - request.requestedAt < 24 * 60 * 60 * 1_000 else { continue }
                let destinations: Set<String>
                if let target = request.targetEndpointId {
                    destinations = Set(meshComputerRoomByEndpointId[target].map { [$0] } ?? [])
                } else {
                    destinations = rooms
                }
                for room in destinations where rooms.contains(room) {
                    let answered = observed.contains { response in
                        response.requestId == requestId
                            && meshComputerRoomByEndpointId[response.endpointId] == room
                    }
                    if !answered { relaysByRoom[room]?.sendProjectCapabilityRequest(request) }
                }
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let clean = trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}

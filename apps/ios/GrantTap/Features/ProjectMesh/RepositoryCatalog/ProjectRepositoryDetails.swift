import Foundation

struct ProjectRepositoryDetails: Codable, Equatable, Identifiable {
    struct Commit: Codable, Equatable, Identifiable {
        let sha: String
        let subject: String
        let author: String
        let committedAt: Double
        var id: String { sha }
    }
    struct Contributor: Codable, Equatable, Identifiable {
        let name: String
        let commits: Int
        var id: String { name }
    }
    let projectId: String
    let repositoryId: String
    var canonicalRepositoryId: String? = nil
    let endpointId: String
    let status: String
    var branch: String? = nil
    var revision: String? = nil
    var dirty: Bool? = nil
    var commitCount: Int? = nil
    var commits: [Commit] = []
    var contributors: [Contributor] = []
    var contributorCount: Int? = nil
    let observedAt: Double
    var id: String { "\(endpointId)\u{1f}\(repositoryId)" }

    static func merging(_ old: [Self]?, _ new: [Self]?) -> [Self]? {
        let reports = Dictionary(grouping: (old ?? []) + (new ?? []), by: \.id).values.compactMap {
            $0.max { $0.observedAt < $1.observedAt }
        }.sorted { $0.id < $1.id }
        return reports.isEmpty ? nil : reports
    }
}

/// Only fresh Git identity reports can join old local IDs with their remote.
enum RepositoryIdentityIndex {
    static func canonical(_ id: String, snapshots: [ProjectMeshSnapshot]) -> String {
        let reports = snapshots.flatMap { snapshot in
            (snapshot.repositoryDetails ?? []).filter {
                $0.projectId == snapshot.projectId && $0.repositoryId == id
            }
        }
        let latest = Dictionary(grouping: reports, by: \.endpointId).values.compactMap {
            $0.max { $0.observedAt < $1.observedAt }
        }
        guard !latest.isEmpty, latest.allSatisfy({ $0.status == "ready" && $0.canonicalRepositoryId != nil }) else { return id }
        let identities = Set(latest.compactMap(\.canonicalRepositoryId))
        return identities.count == 1 ? identities.first! : id
    }
}

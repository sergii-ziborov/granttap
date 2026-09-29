import Foundation

@MainActor
extension AppModel {
    var repositoryVisibleSnapshots: [ProjectMeshSnapshot] {
        projectListRows.filter { !$0.hidden }.compactMap { meshSnapshots[$0.projectId] }
    }

    func repositoryPlacedTasks(projectId: String) -> [ProjectMeshRecency.Row] {
        MeshTaskPlacement.make(snapshots: repositoryVisibleSnapshots, sessions: sessions)
            .filter { $0.projectId == projectId }.map(\.row)
    }

    /// The Mac's durable catalog does not include Git enrichment until requested.
    func observeRepositoryCatalog() async {
        #if targetEnvironment(macCatalyst)
        repeat {
            for snapshot in repositoryVisibleSnapshots.prefix(64) {
                if Task.isCancelled { return }
                await refreshProjectInsights(projectId: snapshot.projectId)
            }
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
        } while !Task.isCancelled
        #endif
    }

    func observeRepositoryDetails(repositoryId: String) async {
        var first = true
        repeat {
            let entries = RepositoryCatalog.make(rows: projectListRows, snapshots: meshSnapshots, sessions: sessions)
            let canonical = RepositoryIdentityIndex.canonical(repositoryId, snapshots: repositoryVisibleSnapshots)
            guard let entry = entries.first(where: { $0.id == canonical }) else { return }
            for member in entry.memberships {
                if Task.isCancelled { return }
                await refreshProjectInsights(projectId: member.projectId, requestRemote: first)
            }
            first = false
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
        } while !Task.isCancelled
    }
}

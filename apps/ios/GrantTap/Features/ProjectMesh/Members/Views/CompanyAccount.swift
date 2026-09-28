import Foundation

/// A company principal is distinct from a Project Mesh participant and from
/// each device paired to the owner's phone. Repository IDs are Engine IDs,
/// never display names or filesystem paths.
enum CompanyRepositoryAccess: Codable, Equatable {
    case all
    case selected(Set<String>)

    func allows(_ repositoryId: String) -> Bool {
        switch self {
        case .all: return true
        case .selected(let ids): return ids.contains(repositoryId)
        }
    }
}

struct CompanyAccount: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var repositoryAccess: CompanyRepositoryAccess
    var disabled = false
}

/// A Project snapshot can contain several repositories. We cannot expose its
/// shared Project key to a partial repository grant and pretend individual
/// rows are hidden. A restricted account must cover every known repository.
enum CompanyAccountPolicy {
    static func repositoryIds(in snapshot: ProjectMeshSnapshot) -> Set<String> {
        var ids: Set<String> = [snapshot.project.canonicalRepositoryId]
        ids.formUnion((snapshot.bindings ?? []).map(\.repositoryId))
        ids.formUnion((snapshot.repositoryGraphs ?? []).map(\.repositoryId))
        ids.formUnion(snapshot.executions.compactMap(\.repositoryId))
        ids.formUnion(snapshot.claims.compactMap(\.repositoryId))
        ids.formUnion((snapshot.peers ?? []).map(\.repositoryId))
        ids.formUnion((snapshot.knowledge ?? []).compactMap(\.repositoryId))
        return ids.filter { !$0.isEmpty }
    }

    static func canReceive(_ snapshot: ProjectMeshSnapshot, account: CompanyAccount) -> Bool {
        guard !account.disabled else { return false }
        let repositories = repositoryIds(in: snapshot)
        return !repositories.isEmpty && repositories.allSatisfy(account.repositoryAccess.allows)
    }
}

/// Account grants are owner-controlled data; pairing secrets stay in their
/// separate keychain store. A failed write never changes the live grant.
enum CompanyAccountStore {
    static let service = "com.ziborov.granttap.company-accounts"
    static let maxAccounts = 64

    static func load(service: String = service) -> [CompanyAccount] {
        guard let data = KeychainPairing.load(service: service),
              let accounts = try? JSONDecoder().decode([CompanyAccount].self, from: data)
        else { return [] }
        return accounts
    }

    @discardableResult
    static func save(_ accounts: [CompanyAccount], service: String = service) -> Bool {
        guard accounts.count <= maxAccounts,
              Set(accounts.map(\.id)).count == accounts.count,
              let data = try? JSONEncoder().encode(accounts)
        else { return false }
        return KeychainPairing.save(data, service: service)
    }

    static func remove(service: String = service) { KeychainPairing.remove(service: service) }
}

@MainActor
extension AppModel {
    /// Both grants must hold. A company grant by itself does not join a Mesh;
    /// a Mesh invitation by itself does not open a repository.
    func memberCanAccessProject(_ link: MemberLink, projectId: String) -> Bool {
        guard link.allowsProject(projectId) else { return false }
        guard let accountId = link.companyAccountId else { return true } // pre-account invite
        guard let account = companyAccounts.first(where: { $0.id == accountId }),
              let snapshot = meshSnapshots[projectId] else { return false }
        return CompanyAccountPolicy.canReceive(snapshot, account: account)
    }

    func memberCanContribute(_ snapshot: ProjectMeshSnapshot, link: MemberLink) -> Bool {
        guard memberCanAccessProject(link, projectId: snapshot.projectId) else { return false }
        guard let accountId = link.companyAccountId else { return true }
        guard let account = companyAccounts.first(where: { $0.id == accountId }) else { return false }
        return CompanyAccountPolicy.canReceive(snapshot, account: account)
    }

    var companyRepositoryIds: [String] {
        Set(meshSnapshots.values.filter { !ownComputerRooms(for: $0.projectId).isEmpty }
            .flatMap { CompanyAccountPolicy.repositoryIds(in: $0) })
            .sorted()
    }

    @discardableResult
    func createCompanyAccount(name: String) -> CompanyAccount? {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !clean.isEmpty else { return nil }
        let account = CompanyAccount(id: UUID().uuidString, name: clean, repositoryAccess: .selected([]))
        let updated = companyAccounts + [account]
        guard CompanyAccountStore.save(updated) else { return nil }
        companyAccounts = updated
        return account
    }

    @discardableResult
    func updateCompanyAccount(_ account: CompanyAccount) -> Bool {
        guard let index = companyAccounts.firstIndex(where: { $0.id == account.id }),
              !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var updated = companyAccounts
        updated[index] = account
        guard CompanyAccountStore.save(updated) else { return false }
        companyAccounts = updated
        for link in memberLinks where link.companyAccountId == account.id {
            reconcileMemberLinkAccess(link)
        }
        return true
    }

    /// Upgrade an old device-only invite without issuing a new pairing.
    /// The account gate begins immediately; there is no way back to legacy.
    @discardableResult
    func assignCompanyAccount(_ accountId: String, to linkId: String) -> Bool {
        guard companyAccounts.contains(where: { $0.id == accountId }),
              let index = memberLinks.firstIndex(where: { $0.id == linkId }),
              memberLinks[index].companyAccountId == nil else { return false }
        var updated = memberLinks
        updated[index].companyAccountId = accountId
        guard MemberLinkStore.save(updated) else { return false }
        memberLinks = updated
        reconcileMemberLinkAccess(updated[index])
        return true
    }

    private func reconcileMemberLinkAccess(_ link: MemberLink) {
        for projectId in link.projectIds {
            meshProjectSourceRooms[projectId]?.remove(link.id)
            if memberCanAccessProject(link, projectId: projectId) {
                meshProjectSourceRooms[projectId, default: []].insert(link.id)
                if memberLinkConnected.contains(link.id) { forwardMemberProject(projectId, to: link) }
            }
        }
        clearMemberPendingRoutes(for: link.id)
    }
}

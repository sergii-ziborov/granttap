import Foundation

/// A paired computer that is not part of this Project, and why.
struct UnboundProjectComputer: Identifiable, Equatable {
    let endpointId: String
    let displayName: String

    var id: String { endpointId }
}

/// Which paired computers take part in this Project's mesh, and which do not.
///
/// The mesh is encrypted under a per-Project key, separate from the pairwise
/// device box. A computer takes part once it holds that key, and the phone is
/// the one place that can hand it over, because it is paired with every
/// computer and already forwards Project snapshots under exactly this grant.
///
/// Membership therefore is not discovered — it is granted, and it is granted
/// from here.
enum ProjectMembership {
    static func unbound(
        snapshot: ProjectMeshSnapshot, paired: [LinkedComputer],
        endpointRooms: [String: String] = [:], participating: Set<String> = []
    ) -> [UnboundProjectComputer] {
        let endpoints = ProjectManagePresentation.endpointIds(snapshot)
        let bound = Set(endpoints + endpoints.compactMap { endpointRooms[$0] }).union(participating)
        return paired
            .filter { !bound.contains($0.id) }
            .map { UnboundProjectComputer(endpointId: $0.id, displayName: $0.displayName) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                == .orderedAscending }
    }

    /// Only authenticated publisher-to-room mappings can identify endpoint aliases.
    /// Names and identical repository paths never establish computer identity.
    static func computers(snapshot: ProjectMeshSnapshot, paired: [LinkedComputer],
                          endpointRooms: [String: String]) -> [ProjectComputerSummary] {
        let endpoints = ProjectManagePresentation.endpointIds(snapshot)
        let groups = Dictionary(grouping: endpoints) { endpointRooms[$0] ?? $0 }
        return groups.keys.sorted().map { identity in
            let aliases = Set(groups[identity] ?? [])
            let bindings = (snapshot.bindings ?? []).filter { aliases.contains($0.endpointId) }
            let pairedComputer = paired.first { $0.id == identity }
            let canonical = aliases.contains(snapshot.publisherEndpointId ?? "")
                ? snapshot.publisherEndpointId! : aliases.sorted().first!
            let name = pairedComputer?.displayName ?? (canonical.count > 24
                ? "\(L("Computer")) \(canonical.prefix(8))" : canonical)
            return ProjectComputerSummary(endpointId: canonical, displayName: name,
                repositoryCount: Set(bindings.map(\.repositoryId)).count,
                available: bindings.isEmpty ? snapshot.executions.contains {
                    aliases.contains($0.computerId) && $0.endedAt == nil
                } : bindings.contains(where: \.available))
        }
    }

    /// True when every paired computer already takes part in this Project, so
    /// there is nothing missing to explain.
    static func everyComputerParticipates(
        snapshot: ProjectMeshSnapshot, paired: [LinkedComputer]
    ) -> Bool {
        !paired.isEmpty && unbound(snapshot: snapshot, paired: paired).isEmpty
    }
}


/// Admitting a paired computer to a Project's mesh.
///
/// The key cannot be conjured: it is copied from a computer that already holds
/// it. A Project no computer has reported yet has no key to copy, so admission
/// is refused rather than appearing to succeed and leaving the target unable to
/// decrypt anything it is later sent.
enum ProjectMeshAdmission {
    /// A room already in the Project, to copy the Project key from.
    static func sourceRoom(target: String, participating: Set<String>) -> String? {
        participating.filter { $0 != target }.sorted().first
    }

    static func canAdmit(
        target: String, participating: Set<String>, paired: [LinkedComputer]
    ) -> Bool {
        guard paired.contains(where: { $0.id == target }) else { return false }
        guard !participating.contains(target) else { return false }
        return sourceRoom(target: target, participating: participating) != nil
    }
}


extension ProjectMembership {
    /// Rooms that appeared while the pairing sheet was open.
    ///
    /// The sheet reports that pairing succeeded but not which computer it was,
    /// and comparing against the rooms known beforehand is the only thing that
    /// answers "the one just scanned" without changing that shared surface.
    static func newlyPaired(before: Set<String>, paired: [LinkedComputer]) -> [String] {
        paired.map(\.id).filter { !before.contains($0) }.sorted()
    }
}

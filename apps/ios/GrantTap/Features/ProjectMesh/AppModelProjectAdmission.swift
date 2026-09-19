import Foundation

extension AppModel {
    /// Hand a paired computer the Project key so it can take part in the mesh.
    ///
    /// The mesh is encrypted under a per-Project key, separate from the pairwise
    /// device box, and the phone is the only party paired with every computer.
    /// Until this existed a computer could only join a Project it had already
    /// reported — which it cannot do before it holds the key.
    ///
    /// The key is copied from a computer that already holds it and travels the
    /// same grant every other Project forward uses.
    @discardableResult
    func admitComputerToProject(projectId: String, room target: String) -> Bool {
        let participating = meshProjectSourceRooms[projectId] ?? []
        guard agentMeshPreferences.meshEnabled,
              ProjectMeshAdmission.canAdmit(
                  target: target, participating: participating,
                  paired: connectionRegistry.connections
              ),
              let sourceRoom = ProjectMeshAdmission.sourceRoom(
                  target: target, participating: participating
              ),
              let snapshot = meshSnapshots[projectId],
              let source = meshRelay(forRoom: sourceRoom),
              let relay = meshRelay(forRoom: target),
              let key = source.sessionKey(for: projectId)
        else { return false }
        relay.forwardMesh(snapshot, scopeId: projectId, key: key, purpose: "project") {
            [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.append("project admission failed: \(error.localizedDescription)")
            }
        }
        // An admitted computer receives every later Project forward, not just this one.
        meshProjectSourceRooms[projectId, default: []].insert(target)
        rememberComputerAdmission(projectId: projectId, endpointId: target)
        return true
    }

    /// Admit whatever pairing just added, so scanning a code both pairs the
    /// computer and puts it in the Project the scan started from.
    @discardableResult
    func admitNewlyPairedComputers(projectId: String, pairedBefore: Set<String>) -> [String] {
        ProjectMembership.newlyPaired(
            before: pairedBefore, paired: connectionRegistry.connections
        ).filter { admitComputerToProject(projectId: projectId, room: $0) }
    }
}

import Foundation

extension AppModel {
    func archivedComputers(for projectId: String) -> Set<String> {
        archivedProjectComputers[projectId] ?? []
    }

    func removedComputers(for projectId: String) -> Set<String> {
        removedProjectComputers[projectId] ?? []
    }

    func hiddenComputers(for projectId: String) -> Set<String> {
        expandComputerIds(
            archivedComputers(for: projectId).union(removedComputers(for: projectId)),
            projectId: projectId
        )
    }

    func computerDisposition(_ endpointId: String, projectId: String) -> ProjectComputerDisposition {
        let aliases = Set(rooms(matching: endpointId, projectId: projectId) + [endpointId])
        if !aliases.isDisjoint(with: removedComputers(for: projectId)) { return .removed }
        if !aliases.isDisjoint(with: archivedComputers(for: projectId)) { return .archived }
        return .active
    }

    func displayName(forComputer endpointId: String) -> String {
        if let connection = connection(matching: endpointId) {
            return connection.displayName
        }
        guard endpointId.count > 24 else { return endpointId }
        return "\(L("Computer")) \(endpointId.prefix(8))"
    }

    func connection(matching endpointId: String) -> LinkedComputer? {
        connectionRegistry.connections.first { $0.id == endpointId }
            ?? connectionRegistry.connections.first { $0.lastMachineName == endpointId }
            ?? connectionRegistry.connections.first { $0.displayName == endpointId }
    }

    func rooms(matching endpointId: String, projectId: String) -> [String] {
        var rooms = Set<String>()
        if (meshProjectSourceRooms[projectId] ?? []).contains(endpointId) {
            rooms.insert(endpointId)
        }
        if let connection = connection(matching: endpointId) {
            rooms.insert(connection.id)
        }
        return rooms.sorted()
    }

    func isRemovedRoom(_ room: String, projectId: String) -> Bool {
        computerDisposition(room, projectId: projectId) == .removed
    }

    func rememberProjectRoom(_ room: String, projectId: String) {
        guard !isRemovedRoom(room, projectId: projectId) else { return }
        meshProjectSourceRooms[projectId, default: []].insert(room)
    }

    @discardableResult
    func archiveProjectComputer(projectId: String, endpointId: String) -> Bool {
        guard computerDisposition(endpointId, projectId: projectId) == .active else { return false }
        var archived = archivedProjectComputers[projectId] ?? []
        archived.insert(endpointId)
        archivedProjectComputers[projectId] = archived
        persistMeshState()
        objectWillChange.send()
        return true
    }

    @discardableResult
    func restoreProjectComputer(projectId: String, endpointId: String) -> Bool {
        guard computerDisposition(endpointId, projectId: projectId) == .archived else { return false }
        var archived = archivedProjectComputers[projectId] ?? []
        archived.remove(endpointId)
        rooms(matching: endpointId, projectId: projectId).forEach { archived.remove($0) }
        if archived.isEmpty {
            archivedProjectComputers.removeValue(forKey: projectId)
        } else {
            archivedProjectComputers[projectId] = archived
        }
        persistMeshState()
        objectWillChange.send()
        return true
    }

    @discardableResult
    func removeProjectComputer(projectId: String, endpointId: String) -> Bool {
        guard computerDisposition(endpointId, projectId: projectId) != .removed else { return false }
        var removed = removedProjectComputers[projectId] ?? []
        removed.insert(endpointId)
        rooms(matching: endpointId, projectId: projectId).forEach { removed.insert($0) }
        removedProjectComputers[projectId] = removed
        var archived = archivedProjectComputers[projectId] ?? []
        archived.remove(endpointId)
        rooms(matching: endpointId, projectId: projectId).forEach { archived.remove($0) }
        if archived.isEmpty {
            archivedProjectComputers.removeValue(forKey: projectId)
        } else {
            archivedProjectComputers[projectId] = archived
        }
        for room in rooms(matching: endpointId, projectId: projectId) {
            meshProjectSourceRooms[projectId]?.remove(room)
        }
        unpinIfHost(projectId: projectId, endpointId: endpointId)
        persistMeshState()
        objectWillChange.send()
        return true
    }

    func unlinkProjectComputer(projectId: String, endpointId: String) {
        removeProjectComputer(projectId: projectId, endpointId: endpointId)
        if let connection = connection(matching: endpointId) {
            unlinkConnection(roomId: connection.id)
        }
    }

    func rememberComputerAdmission(projectId: String, endpointId: String) {
        clearComputerFlags(projectId: projectId, endpointId: endpointId)
        persistMeshState()
    }

    private func clearComputerFlags(projectId: String, endpointId: String) {
        let aliases = Set(rooms(matching: endpointId, projectId: projectId) + [endpointId])
        if var archived = archivedProjectComputers[projectId] {
            archived.subtract(aliases)
            if archived.isEmpty {
                archivedProjectComputers.removeValue(forKey: projectId)
            } else {
                archivedProjectComputers[projectId] = archived
            }
        }
        if var removed = removedProjectComputers[projectId] {
            removed.subtract(aliases)
            if removed.isEmpty {
                removedProjectComputers.removeValue(forKey: projectId)
            } else {
                removedProjectComputers[projectId] = removed
            }
        }
    }

    private func expandComputerIds(_ ids: Set<String>, projectId: String) -> Set<String> {
        var expanded = ids
        for id in ids {
            rooms(matching: id, projectId: projectId).forEach { expanded.insert($0) }
        }
        return expanded
    }

    private func unpinIfHost(projectId: String, endpointId: String) {
        let aliases = Set(rooms(matching: endpointId, projectId: projectId) + [endpointId])
        let snapshot = meshSnapshots[projectId]
        let policy = snapshot?.execution ?? projectGovernance[projectId]?.policy?.execution
        guard policy?.mode == .pinned,
              let host = policy?.targetEndpointId,
              aliases.contains(host) else { return }
        _ = applyProjectExecution(
            projectId: projectId,
            mode: .distributed,
            targetEndpointId: nil,
            offlineBehavior: policy?.offlineBehavior ?? .reject
        )
    }
}

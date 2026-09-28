import Foundation

@MainActor
extension AppModel {
    func projectAutoAcceptLevel(projectId: String, roomId: String) -> String? {
        autoAcceptByProjectByRoom[roomId]?[projectId]
    }

    func desiredProjectAutoAcceptLevel(projectId: String) -> String {
        #if targetEnvironment(macCatalyst)
        if let reader = localMCPReader, reader.isReady,
           !reader.pendingAutoAcceptProjects.contains(projectId),
           let actual = autoAcceptByProjectByRoom["local-mac"]?[projectId] { return actual }
        #endif
        if let desired = desiredAutoAcceptByProject[projectId] { return desired }
        let reported = Set(autoAcceptByProjectByRoom.values.compactMap { $0[projectId] })
        return reported.count == 1 ? reported.first! : AutoAcceptLevel.ask.rawValue
    }

    func migrateProjectAutoAcceptIfNeeded(projectId: String) {
        guard desiredAutoAcceptByProject[projectId] == nil else { return }
        // Conflicting historical endpoint values become ASK rather than the
        // most permissive value or a hidden machine default.
        desiredAutoAcceptByProject[projectId] = desiredProjectAutoAcceptLevel(projectId: projectId)
    }

    /// Save one Project-owned desired level and deliver it independently to
    /// every participating computer. Endpoint reports decide whether it is
    /// applied; this method never edits the machine-global default.
    @discardableResult
    func setProjectAutoAccept(projectId: String, level: String) -> Bool {
        guard !projectId.isEmpty, projectId.count <= 128,
              Self.autoAcceptLevels.contains(level) else { return false }
        #if targetEnvironment(macCatalyst)
        let localSubmitted = setLocalProjectAutoAccept(projectId: projectId, level: level)
        #else
        let localSubmitted = false
        #endif
        let rooms = meshProjectSourceRooms[projectId] ?? []
        guard localSubmitted || !rooms.isEmpty else { return false }
        desiredAutoAcceptByProject[projectId] = level
        for room in rooms {
            relaysByRoom[room]?.sendProjectAutoAccept(
                projectId: projectId,
                level: level,
                baseRevision: configRevisionByRoom[room],
                instanceEpoch: instanceEpochByRoom[room]
            )
        }
        AuditStore.shared.record("auto-accept", detail: "Mesh rule saved and offered to computers")
        return true
    }
}

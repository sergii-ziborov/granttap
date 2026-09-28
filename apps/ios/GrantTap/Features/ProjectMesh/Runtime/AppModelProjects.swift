import Foundation

extension AppModel {
    static func handoffRoute(provider: String, computer: String) -> String {
        "\(provider.lowercased())\u{1f}\(computer)"
    }

    /// The name the person gave a Project, else the one its repository has.
    func projectDisplayName(_ snapshot: ProjectMeshSnapshot) -> String {
        ProjectsCatalog.displayName(snapshot, preference: projectPreferences[snapshot.projectId])
    }

    func projectDisplayName(id projectId: String) -> String? {
        meshSnapshots[projectId].map(projectDisplayName)
    }

    func isProjectHidden(_ projectId: String) -> Bool {
        projectPreferences[projectId]?.hidden == true
    }

    /// A hidden Project leaves every list; its chats stay chats.
    func setProjectHidden(_ projectId: String, _ hidden: Bool, now: Double = Date().timeIntervalSince1970 * 1_000) {
        var preference = projectPreferences[projectId] ?? ProjectPreference()
        preference.hidden = hidden
        preference.hiddenAt = hidden ? now : nil
        projectPreferences[projectId] = preference
        AuditStore.shared.record("mesh", detail: hidden ? "project hidden" : "project shown")
    }

    /// An empty name gives the repository's name back.
    func renameProject(_ projectId: String, to name: String) {
        var preference = projectPreferences[projectId] ?? ProjectPreference()
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        preference.customName = clean.isEmpty ? nil : String(clean.prefix(80))
        projectPreferences[projectId] = preference
        AuditStore.shared.record("mesh", detail: clean.isEmpty ? "project name reset" : "project renamed")
    }

    /// Drop everything this phone holds about a Project. A computer that still
    /// carries it reports it again; a Project that is over stays gone.
    func forgetProject(_ projectId: String) {
        for link in memberLinks.filter({ $0.allowsProject(projectId) }) {
            if link.projectId == projectId {
                guard removeMemberLink(id: link.id) else { return }
            } else {
                var updated = link
                updated.sharedProjectIds = link.projectIds.subtracting([projectId]).sorted()
                guard updateMemberLink(updated) else { return }
            }
        }
        let eventIds = Set((meshSnapshots[projectId]?.events ?? []).map(\.eventId)
            + pendingMeshEvents.filter { $0.projectId == projectId }.map(\.eventId))
        meshSnapshots.removeValue(forKey: projectId)
        pendingMeshEvents.removeAll { $0.projectId == projectId }
        for eventId in eventIds {
            meshAttentionStates.removeValue(forKey: eventId)
            meshEventSourceRooms.removeValue(forKey: eventId)
        }
        meshProjectSourceRooms.removeValue(forKey: projectId)
        projectGovernance.removeValue(forKey: projectId)
        projectPolicyDrafts.removeValue(forKey: projectId)
        projectPreferences.removeValue(forKey: projectId)
        persistMeshState()
        AuditStore.shared.record("mesh", detail: "project forgotten")
    }

    var projectListRows: [ProjectListRow] {
        ProjectsCatalog.rows(
            snapshots: Array(meshSnapshots.values), sessions: sessions, preferences: projectPreferences,
            memberLinks: memberLinks, rooms: meshProjectSourceRooms, connections: connectionRegistry.connections,
            localProjectIds: localMeshProjectIds
        )
    }
}

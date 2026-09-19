import Foundation

enum ProjectMeshAttentionStatus: String, Codable {
    case pending
    case snoozed
    case answered
    case declined
    case acknowledged
    case resolved
}

struct ProjectMeshAttentionState: Codable, Equatable {
    var status: ProjectMeshAttentionStatus
    var snoozedUntil: Double? = nil
    var createdAt: Double? = nil
    var presentedAt: Double? = nil
    var updatedAt: Double? = nil
}

struct ProjectMeshArchive: Codable {
    var snapshots: [String: ProjectMeshSnapshot]
    var pendingEvents: [ProjectMeshEvent]
    var eventSourceRooms: [String: String]
    var attentionStates: [String: ProjectMeshAttentionState]
    /// Which pairing rooms carry which Project.
    ///
    /// This was in-memory only, so a relaunch forgot it until the next
    /// snapshot arrived — up to thirty seconds in which the phone believed it
    /// held no Project key and Governance had nobody to send a policy to.
    var projectRooms: [String: [String]]

    init(
        snapshots: [String: ProjectMeshSnapshot],
        pendingEvents: [ProjectMeshEvent],
        eventSourceRooms: [String: String] = [:],
        attentionStates: [String: ProjectMeshAttentionState] = [:],
        projectRooms: [String: [String]] = [:]
    ) {
        self.snapshots = snapshots
        self.pendingEvents = pendingEvents
        self.eventSourceRooms = eventSourceRooms
        self.attentionStates = attentionStates
        self.projectRooms = projectRooms
    }

    private enum CodingKeys: String, CodingKey {
        case snapshots, pendingEvents, eventSourceRooms, attentionStates, projectRooms
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        snapshots = try values.decode([String: ProjectMeshSnapshot].self, forKey: .snapshots)
        pendingEvents = try values.decode([ProjectMeshEvent].self, forKey: .pendingEvents)
        eventSourceRooms = try values.decodeIfPresent(
            [String: String].self, forKey: .eventSourceRooms
        ) ?? [:]
        attentionStates = try values.decodeIfPresent(
            [String: ProjectMeshAttentionState].self, forKey: .attentionStates
        ) ?? [:]
        projectRooms = try values.decodeIfPresent(
            [String: [String]].self, forKey: .projectRooms
        ) ?? [:]
    }
}

enum ProjectMeshPersistence {
    private static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("GrantTap", isDirectory: true)
            .appendingPathComponent("project-mesh.json")
    }

    static func load() -> ProjectMeshArchive {
        guard let url, let data = try? Data(contentsOf: url),
              let archive = try? JSONDecoder().decode(ProjectMeshArchive.self, from: data)
        else { return ProjectMeshArchive(snapshots: [:], pendingEvents: []) }
        // What was archived before a chat split across two Tasks was understood
        // is restored as it was written, and the next snapshot to arrive is up
        // to thirty seconds away. Rejoin on the way in so the list is right
        // from launch rather than after the first publish. Only the snapshots
        // change: rebuilding the archive around them dropped the answered
        // questions and their rooms, which are restored from the same file.
        var restored = archive
        restored.snapshots = archive.snapshots.mapValues {
            ProjectMeshLogic.withoutNestedCursorComposers(ProjectMeshLogic.rejoinSplitChats($0))
        }
        return restored
    }

    static func save(_ archive: ProjectMeshArchive) {
        guard let url, let data = try? JSONEncoder().encode(archive) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var protectedURL = url
            try protectedURL.setResourceValues(values)
        } catch {
            // Keep state in memory. Diagnostics must not weaken actor isolation
            // or expose project metadata from this low-level persistence path.
        }
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

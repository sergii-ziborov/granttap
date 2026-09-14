import Foundation

/// A Governance edit waiting for a computer that is not listening yet.
///
/// A Project policy is not one machine's business, and it must not be lost
/// because a machine was asleep when it was written. The relay holds an
/// encrypted packet for a day once it has one; this is the step before that —
/// the edit sits here, on the phone, until the relay can be handed it for each
/// Project room in turn.
struct ProjectPolicyOutboxEntry: Codable, Equatable, Identifiable {
    let projectId: String
    let revision: Int
    let room: String
    let request: ProjectPolicySet
    let createdAt: Double

    var id: String { "\(projectId)\u{1f}\(revision)\u{1f}\(room)" }
}

enum ProjectPolicyOutboxStore {
    /// A day, matching the lifetime the relay gives the packet itself. Beyond
    /// that the edit is stale and asking again is honest.
    static let maxAgeMs: Double = 24 * 60 * 60 * 1_000
    private static let maxEntries = 64

    private static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("GrantTap", isDirectory: true)
            .appendingPathComponent("project-policy-outbox.json")
    }

    static func load() -> [ProjectPolicyOutboxEntry] {
        guard let url, let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([ProjectPolicyOutboxEntry].self, from: data)
        else { return [] }
        return entries
    }

    static func save(_ entries: [ProjectPolicyOutboxEntry]) {
        guard let url else { return }
        // Newest first, bounded: an outbox that grows without limit is a leak,
        // and the newest revision is the one worth delivering.
        let bounded = entries.sorted { $0.createdAt > $1.createdAt }.prefix(maxEntries)
        guard let data = try? JSONEncoder().encode(Array(bounded)) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            // A policy that cannot be written down is still sent this session.
        }
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

enum ProjectPolicyOutboxLogic {
    /// One entry per Project room, so no member is skipped for being asleep.
    static func entries(
        for request: ProjectPolicySet, rooms: Set<String>, at now: Double
    ) -> [ProjectPolicyOutboxEntry] {
        rooms.sorted().map { room in
            ProjectPolicyOutboxEntry(
                projectId: request.projectId, revision: request.policy.revision,
                room: room, request: request, createdAt: now
            )
        }
    }

    /// What is still worth sending: the newest revision per room, unexpired.
    ///
    /// A superseded revision is dropped rather than delivered behind the one
    /// that replaced it — a computer applying them in order would end on the
    /// older policy.
    static func pending(
        _ entries: [ProjectPolicyOutboxEntry], at now: Double
    ) -> [ProjectPolicyOutboxEntry] {
        var newest: [String: ProjectPolicyOutboxEntry] = [:]
        for entry in entries where now - entry.createdAt <= ProjectPolicyOutboxStore.maxAgeMs {
            let key = "\(entry.projectId)\u{1f}\(entry.room)"
            if let held = newest[key], held.revision >= entry.revision { continue }
            newest[key] = entry
        }
        return newest.values.sorted { $0.id < $1.id }
    }

    /// Everything this delivery settles: the entry sent, and anything it
    /// supersedes for the same room.
    static func settled(
        _ entries: [ProjectPolicyOutboxEntry], delivered: ProjectPolicyOutboxEntry
    ) -> [ProjectPolicyOutboxEntry] {
        entries.filter { entry in
            !(entry.projectId == delivered.projectId && entry.room == delivered.room
              && entry.revision <= delivered.revision)
        }
    }
}

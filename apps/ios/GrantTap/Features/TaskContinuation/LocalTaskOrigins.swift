import Foundation

/// Routing IDs only. Prompt text and attachments remain in the encrypted outbox.
enum LocalTaskOrigins {
    private struct Entry: Codable {
        let sessionId: String
        let agent: String
        let room: String
        let originId: String
        let createdAt: Double
    }
    private static let lifetime: Double = 37 * 86_400_000
    private static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrantTap/task-origins.json")
    }

    static func remember(sessionId: String, agent: String, room: String, originId: String,
                         at: Double, file: URL? = nil) throws {
        let destination = file ?? defaultFile
        var entries = try load(destination)
        if let existing = entries.first(where: { $0.sessionId == sessionId && $0.agent == agent && $0.room == room }) {
            guard existing.originId == originId else { throw RelayTaskQueueError.conflict }
            return
        }
        entries.removeAll { $0.createdAt + lifetime <= at }
        entries.append(Entry(sessionId: sessionId, agent: agent, room: room, originId: originId, createdAt: at))
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: destination,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func origin(sessionId: String, agent: String, room: String, now: Double,
                       file: URL? = nil) throws -> String? {
        try load(file ?? defaultFile).first {
            $0.sessionId == sessionId && $0.agent == agent && $0.room == room
                && $0.createdAt <= now && now < $0.createdAt + lifetime
        }?.originId
    }

    static func routes(room: String, now: Double) throws -> [(agent: String, origin: String, session: String)] {
        try load(defaultFile).filter { $0.room == room && $0.createdAt <= now && now < $0.createdAt + lifetime }
            .map { (agent: $0.agent, origin: $0.originId, session: $0.sessionId) }
    }

    private static func load(_ file: URL) throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))
    }
}

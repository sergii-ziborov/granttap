import Foundation
import OSLog

/// The phone's own copy of the chats it has been shown.
///
/// A transcript used to live only in memory, so every time a chat was opened it
/// was fetched from the Mac and decrypted again — the "Opening the encrypted
/// chat…" wait. That is the wrong place to keep it: the relay deliberately does
/// not store payloads, and the Mac's own copy can be compacted or cleared, so
/// the only durable holder of what the user has already seen is this device.
///
/// The file holds decrypted chat content and is therefore written with the same
/// protection as the pairing cache, and bounded so a phone that accumulates
/// chats forever does not accumulate their transcripts forever too.
enum SessionActivityPersistence {
    /// Chats kept on disk, newest first. Older ones fall out rather than growing.
    static let maxSessions = 60
    /// Entries kept per chat. A long session is truncated from the front, so the
    /// most recent exchange — the part a reopened chat shows — always survives.
    static let maxEntriesPerSession = 300

    private static let filename = "session-activities.json"
    private static let logger = Logger(subsystem: "com.ziborov.granttap",
                                       category: "persistence")

    static func load() -> [String: SessionActivity] {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([String: SessionActivity].self, from: data)
        else { return [:] }
        return stored
    }

    static func save(_ activities: [String: SessionActivity]) {
        guard let data = try? JSONEncoder().encode(bounded(activities)) else { return }
        do {
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true
            )
            try data.write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            logger.error(
                "Transcript cache write failed (code: \((error as NSError).code, privacy: .public))"
            )
        }
    }

    /// Keep the most recent chats, and the most recent exchange within each.
    static func bounded(_ activities: [String: SessionActivity]) -> [String: SessionActivity] {
        let newest = activities.values
            .sorted { $0.generatedAt > $1.generatedAt }
            .prefix(maxSessions)
        return Dictionary(uniqueKeysWithValues: newest.map { activity in
            (activity.sessionId, trimmed(activity))
        })
    }

    private static func trimmed(_ activity: SessionActivity) -> SessionActivity {
        guard activity.entries.count > maxEntriesPerSession else { return activity }
        return SessionActivity(
            type: activity.type, sessionId: activity.sessionId, agent: activity.agent,
            state: activity.state,
            entries: Array(activity.entries.suffix(maxEntriesPerSession)),
            generatedAt: activity.generatedAt
        )
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrantTap", isDirectory: true)
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent(filename)
    }
}

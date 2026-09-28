import Foundation
import OSLog

/// The device’s protected copy of fetched transcript history.
/// Mac keeps per-chat archives; phones retain complete boundaries for the two
/// latest requests and ordinary recent rows. Cleanup is an explicit Settings action.
enum SessionActivityPersistence {
    /// Chats kept on disk, newest first. Older ones fall out rather than growing.
    static let maxSessions = 60
    /// The phone’s ordinary window, extended through its two latest requests.
    /// Mac archives retain every fetched page until explicitly cleared.
    static let maxEntriesPerSession = 300

    private static let filename = "session-activities.json"
    private static let logger = Logger(subsystem: "com.ziborov.granttap",
                                       category: "persistence")

    static func load() -> [String: SessionActivity] {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([String: SessionActivity].self, from: data)
        else {
            #if targetEnvironment(macCatalyst)
            return archive.load()
            #else
            return [:]
            #endif
        }
        #if targetEnvironment(macCatalyst)
        return stored.merging(archive.load()) { _, saved in saved }
        #else
        return stored
        #endif
    }

    static func save(_ activities: [String: SessionActivity]) {
        do {
            #if targetEnvironment(macCatalyst)
            for activity in activities.values { try archive.save(activity) }
            return
            #else
            let data = try JSONEncoder().encode(bounded(activities))
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true
            )
            try data.write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            #endif
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

    static func trimmed(_ activity: SessionActivity) -> SessionActivity {
        #if targetEnvironment(macCatalyst)
        return activity
        #else
        let entries = TranscriptRequestBoundary.retainedEntries(activity.entries, limit: maxEntriesPerSession)
        // A cursor preceding discarded rows would skip a gap. Refetch the latest
        // native page on reopening, then walk backward from its valid cursor.
        let history = entries.count == activity.entries.count ? activity.history : nil
        return SessionActivity(type: activity.type, sessionId: activity.sessionId,
            agent: activity.agent, state: activity.state, threadId: activity.threadId, entries: entries,
            generatedAt: activity.generatedAt, history: history)
        #endif
    }

    static var bytes: Int64 {
        let legacy = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return legacy + archive.bytes
    }

    private static var archive: TranscriptArchive {
        TranscriptArchive(directory: directoryURL.appendingPathComponent("transcripts", isDirectory: true))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        try? archive.clear()
    }

    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrantTap", isDirectory: true)
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent(filename)
    }
}

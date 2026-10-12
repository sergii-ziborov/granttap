import Foundation
import OSLog

/// The device’s protected copy of fetched transcript history.
/// Every fetched page stays on iPhone and Mac until explicitly cleared.
enum SessionActivityPersistence {
    /// Legacy window size; kept for migration/compatibility, never an eviction limit.
    static let maxEntriesPerSession = 300

    private static let filename = "session-activities.json"
    private static let logger = Logger(subsystem: "com.ziborov.granttap",
                                       category: "persistence")

    static func load() -> [String: SessionActivity] {
        let stored = (try? Data(contentsOf: fileURL)).flatMap {
            try? JSONDecoder().decode([String: SessionActivity].self, from: $0)
        } ?? [:]
        return stored.merging(archive.load()) { _, saved in saved }
    }

    static func save(_ activities: [String: SessionActivity]) {
        do {
            for activity in activities.values { try archive.save(activity) }
        } catch {
            logger.error(
                "Transcript cache write failed (code: \((error as NSError).code, privacy: .public))"
            )
        }
    }

    /// Existing callers may still normalize a snapshot; normalization never evicts.
    static func bounded(_ activities: [String: SessionActivity]) -> [String: SessionActivity] {
        activities
    }

    static func trimmed(_ activity: SessionActivity) -> SessionActivity {
        activity
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

import Foundation
import OSLog

enum ArchivedSessionPersistence {
    private static let filename = "archived-sessions.json"
    private static let logger = Logger(subsystem: "com.ziborov.granttap",
                                       category: "persistence")

    static func load() -> [String: SessionInfo] {
        guard let data = try? Data(contentsOf: fileURL),
              let sessions = try? JSONDecoder().decode([String: SessionInfo].self, from: data) else {
            return [:]
        }
        return sessions
    }

    static func save(_ sessions: [String: SessionInfo]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Archived-session cache write failed (code: \((error as NSError).code, privacy: .public))")
        }
    }

    static func remove() { try? FileManager.default.removeItem(at: fileURL) }

    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrantTap", isDirectory: true)
    }
    private static var fileURL: URL { directoryURL.appendingPathComponent(filename) }
}

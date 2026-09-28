import Foundation
import CryptoKit

/// Per-chat Mac archive: fetched pages remain available across app launches.
/// Filenames are hashes of ids; malformed records cannot replace another chat.
struct TranscriptArchive {
    let directory: URL

    func load() -> [String: SessionActivity] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil)) ?? []
        var result: [String: SessionActivity] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let activity = try? JSONDecoder().decode(SessionActivity.self, from: data),
                  file.lastPathComponent == filename(activity.sessionId) else { continue }
            result[activity.sessionId] = activity
        }
        return result
    }

    func save(_ activity: SessionActivity) throws {
        let data = try JSONEncoder().encode(activity)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(filename(activity.sessionId))
        if (try? Data(contentsOf: file)) == data { return }
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    var bytes: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { total, file in
            total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func filename(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }
}

import Foundation
import CryptoKit

struct TaskWorkspaceStore {
    let directory: URL
    static var shared: Self {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Self(directory: root.appendingPathComponent("GrantTap/workspace-previews"))
    }

    func load(scope: String, sessionId: String, mode: String, path: String, offset: Int) -> TaskWorkspaceSnapshot? {
        guard let bytes = try? Data(contentsOf: file(scope, sessionId, mode, path, offset)),
              let result = try? JSONDecoder().decode(TaskWorkspaceSnapshot.self, from: bytes),
              result.isWellFormed, result.sessionId == sessionId, result.path == path,
              mode == "directory" ? result.entries != nil : result.text != nil else { return nil }
        return result
    }

    func save(_ result: TaskWorkspaceSnapshot, scope: String, mode: String, offset: Int) {
        guard result.isWellFormed, result.unavailable != true else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let bytes = try? JSONEncoder().encode(result) {
            try? bytes.write(to: file(scope, result.sessionId, mode, result.path, offset),
                             options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func clear() { try? FileManager.default.removeItem(at: directory) }

    var bytes: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    private func file(_ scope: String, _ sessionId: String, _ mode: String, _ path: String, _ offset: Int) -> URL {
        let identity = [scope, sessionId, mode, path, String(offset)].joined(separator: "\u{0}")
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }
}

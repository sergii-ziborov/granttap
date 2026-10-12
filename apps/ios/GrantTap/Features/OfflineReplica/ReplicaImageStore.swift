import Foundation
import CryptoKit

/// Original image bytes, keyed by authenticated computer + conversation + image.
/// Application Support and file protection retain them across offline launches.
struct ReplicaImageStore {
    let directory: URL

    static var shared: ReplicaImageStore {
        let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        return ReplicaImageStore(directory: root.appendingPathComponent("GrantTap/images"))
    }

    func load(scope: String, sessionId: String, imageId: String) -> Data? {
        try? Data(contentsOf: file(scope: scope, sessionId: sessionId, imageId: imageId))
    }

    func save(_ data: Data, scope: String, sessionId: String, imageId: String) throws {
        guard !data.isEmpty, data.count <= 8 * 1_024 * 1_024 else { throw StorageError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(scope: scope, sessionId: sessionId, imageId: imageId),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remember(_ job: ReplicaImageJob, scope: String) {
        let url = file(scope: scope, sessionId: job.sessionId, imageId: job.imageId)
            .appendingPathExtension("route")
        // Keep the cursor of the page that actually advertised this picture.
        // A merged transcript's oldest cursor describes a different page.
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(job) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func cursor(scope: String, sessionId: String, imageId: String) -> String? {
        let url = file(scope: scope, sessionId: sessionId, imageId: imageId).appendingPathExtension("route")
        guard let data = try? Data(contentsOf: url),
              let job = try? JSONDecoder().decode(ReplicaImageJob.self, from: data),
              job.sessionId == sessionId, job.imageId == imageId else { return nil }
        return job.cursor
    }

    var bytes: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(scope: String, sessionId: String, imageId: String) -> URL {
        let key = [scope, sessionId, imageId].joined(separator: "\u{0}")
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".image")
    }

    enum StorageError: Error { case invalid }
}

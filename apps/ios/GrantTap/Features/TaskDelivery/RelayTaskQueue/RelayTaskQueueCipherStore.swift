import CryptoKit
import Foundation

/// Large immutable ciphertext lives outside the frequently rewritten outbox metadata.
enum RelayTaskQueueCipherStore {
    private static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RelayTaskQueue", isDirectory: true)
    }

    static func save(_ value: RelayTaskQueueReservation, directory: URL? = nil) throws -> RelayTaskQueueReservation {
        let url = try path(value.jobId, directory: directory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var metadata = value
        metadata.envelope = nil
        metadata.cipherDigest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return metadata
    }

    static func restore(_ metadata: RelayTaskQueueReservation, directory: URL? = nil) throws -> RelayTaskQueueReservation {
        if metadata.envelope != nil { return metadata }
        let url = try path(metadata.jobId, directory: directory)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let bytes = attributes[.size] as? NSNumber, bytes.intValue <= 22_100_000 else {
            throw RelayTaskQueueError.invalidMessage
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == metadata.cipherDigest else { throw RelayTaskQueueError.invalidMessage }
        let value = try JSONDecoder().decode(RelayTaskQueueReservation.self, from: data)
        guard value.jobId == metadata.jobId, value.token == metadata.token,
              value.notBefore == metadata.notBefore, value.expiresAt == metadata.expiresAt,
              value.envelope != nil else { throw RelayTaskQueueError.invalidMessage }
        return value
    }

    static func remove(_ id: String, directory: URL? = nil) {
        guard let url = try? path(id, directory: directory) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func path(_ id: String, directory: URL?) throws -> URL {
        guard id.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{7,119}$", options: .regularExpression) != nil else {
            throw RelayTaskQueueError.invalidMessage
        }
        return (directory ?? root).appendingPathComponent(id).appendingPathExtension("json")
    }
}

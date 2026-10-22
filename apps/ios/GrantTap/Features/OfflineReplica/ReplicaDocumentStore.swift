import CryptoKit
import Foundation

/// Submitted documents and their native aliases share the bounded, protected
/// attachment archive. A small manifest avoids decoding document bodies to list them.
struct ReplicaDocumentStore {
    let directory: URL
    static var shared: Self { .init(directory: ReplicaImageStore.shared.directory) }

    func save(_ documents: [AttachmentDraft], scope: String, sessionId: String, entryId: String) throws {
        try AttachmentDraft.validateTotal(documents)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for document in documents {
            let data = try JSONEncoder().encode(document.payload)
            try data.write(to: file(scope, sessionId, entryId, document.name),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        let names = try JSONEncoder().encode(documents.map(\.name))
        try names.write(to: file(scope, sessionId, entryId, nil),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        ReplicaImageStore(directory: directory).prune()
    }

    func names(scope: String, sessionId: String, entryId: String) -> [String] {
        guard let data = try? Data(contentsOf: file(scope, sessionId, entryId, nil)) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func load(scope: String, sessionId: String, entryId: String, name: String) -> AttachmentDraft? {
        let url = file(scope, sessionId, entryId, name)
        guard let data = try? Data(contentsOf: url), data.count <= 8_100_000,
              let document = try? JSONDecoder().decode(UserAttachment.self, from: data),
              document.name == name, let bytes = Data(base64Encoded: document.data),
              bytes.count <= AttachmentDraft.maxBytes else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        try? FileManager.default.setAttributes([.modificationDate: Date()],
            ofItemAtPath: file(scope, sessionId, entryId, nil).path)
        return .init(name: name, mimeType: document.mimeType, data: bytes)
    }

    private func file(_ scope: String, _ session: String, _ entry: String, _ name: String?) -> URL {
        let key = [scope, session, entry, name ?? ""].joined(separator: "\u{0}")
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + (name == nil ? ".names" : ".document"))
    }
}

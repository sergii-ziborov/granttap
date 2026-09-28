#if targetEnvironment(macCatalyst)
import Foundation

/// The socket carries only a small manifest; file bytes stay in a private same-user directory.
final class MacLocalAttachmentBatch {
    let directory: URL
    let manifest: String

    init(_ attachments: [AttachmentDraft]) throws {
        try AttachmentDraft.validateTotal(attachments)
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("granttap-message-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        do {
            var files: [[String: String]] = []
            for (index, attachment) in attachments.enumerated() {
                let url = directory.appendingPathComponent(String(index))
                try attachment.data.write(to: url)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                files.append(["path": url.path, "name": attachment.name, "mimeType": attachment.mimeType])
            }
            manifest = String(decoding: try JSONSerialization.data(withJSONObject: files), as: UTF8.self)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
    deinit { remove() }
}
#endif

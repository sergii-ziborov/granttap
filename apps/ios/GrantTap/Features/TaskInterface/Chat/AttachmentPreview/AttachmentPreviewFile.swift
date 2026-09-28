import Foundation
import QuickLook
import UniformTypeIdentifiers

/// A private copy owned by one preview. Removing a draft never changes the source file.
final class AttachmentPreviewFile: NSObject, Identifiable, QLPreviewItem {
    let id = UUID()
    let name: String
    let data: Data
    let directory: URL
    let url: URL

    init(_ attachment: AttachmentDraft) throws {
        name = attachment.name
        data = attachment.data
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("granttap-preview-\(UUID().uuidString)", isDirectory: true)
        url = directory.appendingPathComponent((name as NSString).lastPathComponent)
        super.init()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        do {
            try data.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
    var previewItemURL: URL? { url }
    var previewItemTitle: String? { name }

    var canPreview: Bool {
        #if targetEnvironment(macCatalyst)
        QLPreviewController.canPreviewItem(self)
        #else
        QLPreviewController.canPreview(self)
        #endif
    }

    var text: String? {
        let type = UTType(filenameExtension: url.pathExtension)
        guard type?.conforms(to: .rtf) != true,
              type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true
            else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
    }
}

import SwiftUI
import ImageIO

@MainActor
final class MessageImageLoader: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]
    @Published private(set) var failed = Set<String>()

    /// Sequential reads keep a gallery from exhausting the MCP socket limit.
    func load(_ attachments: [MessageImageAttachment],
              data: (MessageImageAttachment) async throws -> Data) async {
        for attachment in attachments where images[attachment.id] == nil {
            guard !Task.isCancelled else { return }
            do {
                let bytes = try await data(attachment)
                guard !Task.isCancelled else { return }
                guard let image = Self.thumbnail(bytes) else { throw ImageError.invalid }
                images[attachment.id] = image
                failed.remove(attachment.id)
            } catch {
                guard !Task.isCancelled else { return }
                failed.insert(attachment.id)
            }
        }
    }

    static func thumbnail(_ bytes: Data) -> UIImage? {
        guard !bytes.isEmpty, bytes.count <= 8 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_048,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    enum ImageError: Error { case unavailable, invalid }
}

import Foundation

/// Icon for an attachment the chat can only identify by filename.
///
/// The bridge deliberately sends names without paths or bytes, so the picture
/// itself is not available to render — a truthful icon plus the real filename is
/// what the phone can honestly show.
enum AttachmentGlyph {
    static func forName(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp":
            return "photo"
        case "mov", "mp4", "m4v", "avi", "mkv":
            return "video"
        case "pdf":
            return "doc.richtext"
        case "zip", "gz", "tar", "7z":
            return "doc.zipper"
        case "txt", "md", "rtf", "log":
            return "doc.text"
        default:
            return "paperclip"
        }
    }
}

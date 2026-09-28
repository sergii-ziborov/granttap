import Foundation

/// A runtime-advertised picture in a visible message. The identifier is scoped
/// to its Task; Markdown is retained only to place the preview in the message.
struct MessageImageAttachment: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let markdown: String

    var isValid: Bool {
        !id.isEmpty && id.utf16.count <= 512 && !name.isEmpty && name.utf16.count <= 256
            && !markdown.isEmpty && markdown.utf16.count <= 2_400
    }
}

import Foundation

enum MessageImageContent {
    enum Part: Equatable {
        case text(String)
        case images([MessageImageAttachment])
    }

    /// Consecutive image links become a gallery at their original position.
    /// Ordinary paragraphs, tables and code retain their original Markdown.
    static func parts(_ text: String, images: [MessageImageAttachment]) -> [Part] {
        let valid = images.filter(\.isValid)
        guard !valid.isEmpty else { return [.text(text)] }
        var result: [Part] = []
        var prose: [String] = []
        var gallery: [MessageImageAttachment] = []
        var displayed = Set<String>()
        func flushProse() {
            let body = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { result.append(.text(body)) }
            prose = []
        }
        func flushGallery() {
            if !gallery.isEmpty { result.append(.images(gallery)) }
            gallery = []
        }
        for line in text.components(separatedBy: "\n") {
            let token = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: #"^(?:[-*+] |\d+\. )"#, with: "", options: .regularExpression)
            if let image = valid.first(where: { $0.markdown == token }) {
                flushProse()
                if displayed.insert(image.id).inserted { gallery.append(image) }
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty, !gallery.isEmpty {
                continue
            } else {
                flushGallery()
                prose.append(line)
            }
        }
        flushProse()
        flushGallery()
        let inline = valid.filter { !displayed.contains($0.id) && text.contains($0.markdown) }
        if !inline.isEmpty { result.append(.images(inline)) }
        return result.isEmpty ? [.text(text)] : result
    }
}

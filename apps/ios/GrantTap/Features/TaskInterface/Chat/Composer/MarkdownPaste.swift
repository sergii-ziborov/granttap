import Foundation

enum MarkdownPaste {
    /// Ordinary short prose stays in the field. Structured Markdown and long
    /// pasted text travel as files, preserving every UTF-8 byte for preview.
    static func attachment(for text: String) -> AttachmentDraft? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let markers = [#"(?m)^\s{0,3}#{1,6}\s+\S"#, #"(?m)^\s*(```|~~~)"#,
            #"(?m)^\s*\|?\s*:?-{3,}:?\s*\|"#, #"\*\*[^\n]+\*\*"#,
            #"\[[^\]\n]+\]\([^\)\n]+\)"#, #"(?m)^\s{0,3}(?:[-*+]|\d+[.)]|>)\s+\S"#,
            #"(?<!\w)(?:\*[^*\n]+\*|_[^_\n]+_)(?!\w)"#, #"(?m)^\s{0,3}(?:-{3,}|\*{3,}|_{3,})\s*$"#]
        let markdown = markers.contains {
            text.range(of: $0, options: .regularExpression) != nil
        }
        guard markdown || text.utf16.count > 4_000 else { return nil }
        return AttachmentDraft(name: markdown ? "Pasted.md" : "Pasted.txt",
                               mimeType: markdown ? "text/markdown" : "text/plain", data: Data(text.utf8))
    }

    static func append(_ text: String, to attachments: inout [AttachmentDraft]) throws -> Bool {
        guard text.utf8.count <= AttachmentDraft.maxBytes else { throw AttachmentDraft.Error.tooLarge("Pasted.txt") }
        guard var file = attachment(for: text) else { return false }
        let ext = (file.name as NSString).pathExtension
        var number = 2
        while attachments.contains(where: { $0.name == file.name }) {
            file = .init(name: "Pasted-\(number).\(ext)", mimeType: file.mimeType, data: file.data)
            number += 1
        }
        try AttachmentDraft.validateTotal(attachments + [file])
        attachments.append(file)
        return true
    }
}

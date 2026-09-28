import Foundation

enum TaskDisplayTitle {
    private static let link = try? NSRegularExpression(
        pattern: #"\[([^\]\n]{1,160})\]\((?:plugin|https?)://[^)\s]{1,512}\)"#
    )

    static func plain(_ title: String) -> String {
        let normalized = title.replacingOccurrences(of: #"\s+"#, with: " ",
                                                    options: .regularExpression)
        let result: String
        if let link {
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            result = link.stringByReplacingMatches(in: normalized, range: range, withTemplate: "$1")
        } else {
            result = normalized
        }
        let clean = result
            .replacingOccurrences(of: #"^\s*(?:#{1,6}\s*|[-*]\s+)"#, with: "",
                                  options: .regularExpression)
            .replacingOccurrences(of: #"\*\*|__|`"#, with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty || clean.range(of: #"^task[-_][A-Za-z0-9_-]{8,}$"#,
                                        options: .regularExpression) != nil {
            return "Untitled Task"
        }
        return clean
    }

    static func compact(_ title: String) -> String {
        let clean = plain(title)
        guard clean.count > 72 else { return clean }
        let prefix = String(clean.prefix(72))
        let trimmed = prefix.lastIndex(of: " ").map { String(prefix[..<$0]) } ?? prefix
        return trimmed + "…"
    }
}

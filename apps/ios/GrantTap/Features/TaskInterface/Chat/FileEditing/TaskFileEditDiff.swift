import Foundation

/// Linear, bounded review output; the request attachment carries the complete exact texts.
struct TaskFileEditDiff {
    let text: String
    let truncated: Bool

    init(original: String, proposed: String, path: String) {
        guard !original.utf8.elementsEqual(proposed.utf8) else {
            text = ""; truncated = false; return
        }
        let before = Self.lines(original), after = Self.lines(proposed)
        var prefix = 0, suffix = 0
        while prefix < min(before.count, after.count),
              before[prefix].utf8.elementsEqual(after[prefix].utf8) { prefix += 1 }
        if prefix == before.count, prefix == after.count { prefix = max(0, prefix - 1) }
        while original.hasSuffix("\n") == proposed.hasSuffix("\n"),
              suffix < min(before.count, after.count) - prefix,
              before[before.count - suffix - 1].utf8.elementsEqual(after[after.count - suffix - 1].utf8) {
            suffix += 1
        }
        let start = max(0, prefix - 3)
        let oldEnd = before.count - max(0, suffix - 3), newEnd = after.count - max(0, suffix - 3)
        var result = ["--- a/\(path)", "+++ b/\(path)",
            "@@ -\(oldEnd == start ? start : start + 1),\(oldEnd - start) +\(newEnd == start ? start : start + 1),\(newEnd - start) @@"]
        result += Self.marked(before, start..<prefix, " ", original)
        result += Self.marked(before, prefix..<(before.count - suffix), "-", original)
        result += Self.marked(after, prefix..<(after.count - suffix), "+", proposed)
        result += Self.marked(after, (after.count - suffix)..<newEnd, " ", proposed)
        truncated = result.count > 400
        text = (truncated ? Array(result.prefix(200)) + ["…"] + Array(result.suffix(200)) : result)
            .joined(separator: "\n")
    }

    private static func lines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    private static func marked(_ lines: [String], _ range: Range<Int>, _ mark: String,
                               _ source: String) -> [String] {
        range.flatMap { index in
            [mark + lines[index]] + (index == lines.count - 1 && !source.hasSuffix("\n")
                ? ["\\ No newline at end of file"] : [])
        }
    }
}

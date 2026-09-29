import Foundation

/// Paging and retention share the same definition of a person’s request.
enum TranscriptRequestBoundary {
    private struct Request {
        var entry: ActivityEntry
        let start: Int
        var end: Int
    }

    static func isRequest(_ entry: ActivityEntry) -> Bool {
        entry.kind == "user" && entry.childThreadId == nil
            && (!entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || entry.attachments?.isEmpty == false || entry.images?.isEmpty == false)
    }

    static func previous(in entries: [ActivityEntry], before id: String?) -> ActivityEntry? {
        let requests = requests(in: entries)
        let end = id.flatMap { target in entries.firstIndex { $0.id == target } } ?? entries.count
        let boundary = requests.first { $0.start <= end && end < $0.end }?.start ?? end
        return requests.last { $0.start < boundary }?.entry
    }

    static func request(containing id: String, in entries: [ActivityEntry]) -> ActivityEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return requests(in: entries).first { $0.start <= index && index < $0.end }?.entry
    }

    static func needsEarlierPage(in entries: [ActivityEntry], before id: String?) -> Bool {
        if let id { return previous(in: entries, before: id) == nil }
        return requests(in: entries).count < 2
    }

    static func retainedEntries(_ entries: [ActivityEntry], limit: Int) -> [ActivityEntry] {
        let boundary = requests(in: entries).suffix(2).first?.start ?? entries.count
        let start = min(max(0, entries.count - limit), boundary)
        return Array(entries.suffix(from: start))
    }

    /// Native providers can emit a request's text and each attachment as separate
    /// adjacent rows at one timestamp. Keep each real text request distinct.
    private static func requests(in entries: [ActivityEntry]) -> [Request] {
        var result: [Request] = []
        for (index, entry) in entries.enumerated() where isRequest(entry) {
            let hasText = !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if let last = result.last, last.end == index, last.entry.createdAt == entry.createdAt,
               !hasText || last.entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result[result.count - 1].end = index + 1
                if hasText { result[result.count - 1].entry = entry }
            } else {
                result.append(Request(entry: entry, start: index, end: index + 1))
            }
        }
        return result
    }
}

import Foundation

/// Paging and retention share the same definition of a person’s request.
enum TranscriptRequestBoundary {
    static func isRequest(_ entry: ActivityEntry) -> Bool {
        entry.kind == "user" && entry.childThreadId == nil
            && (!entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || entry.attachments?.isEmpty == false || entry.images?.isEmpty == false)
    }

    static func previous(in entries: [ActivityEntry], before id: String?) -> ActivityEntry? {
        let end = id.flatMap { target in entries.firstIndex { $0.id == target } } ?? entries.count
        return entries.prefix(end).last(where: isRequest)
    }

    static func needsEarlierPage(in entries: [ActivityEntry], before id: String?) -> Bool {
        if let id { return previous(in: entries, before: id) == nil }
        return entries.lazy.filter(isRequest).prefix(2).count < 2
    }

    static func retainedEntries(_ entries: [ActivityEntry], limit: Int) -> [ActivityEntry] {
        let requests = entries.indices.filter { isRequest(entries[$0]) }
        let boundary = requests.suffix(2).first ?? entries.count
        let start = min(max(0, entries.count - limit), boundary)
        return Array(entries.suffix(from: start))
    }
}

import Foundation

/// Recorded work for one root user request, including its attachment fragments.
struct ChatRequestWork {
    let entries: [ActivityEntry]
    let threads: [ChildThreadDisplayRow]
    let files: [RecordedFileChange]

    init(requestId: String?, entries: [ActivityEntry], threads: [ChildThreadDisplayRow]) {
        let index = TranscriptRequestIndex(entries)
        guard let requestId, let request = index.request(containing: requestId),
              let start = entries.firstIndex(where: { index.request(containing: $0.id)?.id == request.id })
        else { self.entries = []; self.threads = []; files = []; return }
        let end = entries.indices.first { position in
            position > start && index.request(containing: entries[position].id).map { $0.id != request.id } == true
        } ?? entries.count
        let nextAt = end < entries.count ? entries[end].createdAt : Double.infinity
        let root = entries[start..<end].filter { $0.childThreadId == nil }
        let nested = entries.filter {
            $0.childThreadId != nil && $0.createdAt >= request.createdAt && $0.createdAt < nextAt
        }
        var included = Set(nested.compactMap(\.childThreadId))
        for row in threads where row.thread.startedAt >= request.createdAt && row.thread.startedAt < nextAt {
            included.insert(row.id)
        }
        self.entries = (root + nested).sorted { $0.createdAt < $1.createdAt }
        self.threads = threads.filter { included.contains($0.id) }
        files = ChatFileChanges.currentReply(entries: Array(root))
    }
}

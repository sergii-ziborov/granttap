import Foundation

/// Prepared with a transcript revision; scroll callbacks only look up positions.
struct TranscriptRequestIndex {
    private struct Request {
        var entry: ActivityEntry
        let start: Int
        var end: Int
    }

    private var requests: [Request] = []
    private var positions: [String: Int] = [:]
    private var groups: [String: Int] = [:]
    private let count: Int

    init(_ entries: [ActivityEntry]) {
        count = entries.count
        for (index, entry) in entries.enumerated() {
            positions[entry.id] = index
            guard TranscriptRequestBoundary.isRequest(entry) else { continue }
            let hasText = !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if let last = requests.last, last.end == index, last.entry.createdAt == entry.createdAt,
               !hasText || last.entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                requests[requests.count - 1].end = index + 1
                if hasText { requests[requests.count - 1].entry = entry }
            } else {
                requests.append(Request(entry: entry, start: index, end: index + 1))
            }
            groups[entry.id] = requests.count - 1
        }
    }

    func request(containing id: String) -> ActivityEntry? {
        groups[id].map { requests[$0].entry }
    }

    func previous(before id: String?) -> ActivityEntry? {
        let position = id.flatMap { positions[$0] } ?? count
        let boundary = id.flatMap { groups[$0] }.map { requests[$0].start } ?? position
        var lower = 0
        var upper = requests.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if requests[middle].start < boundary { lower = middle + 1 }
            else { upper = middle }
        }
        return lower > 0 ? requests[lower - 1].entry : nil
    }

    func needsEarlierPage(before id: String?) -> Bool {
        if let id { return previous(before: id) == nil }
        return requests.count < 2
    }

    func position(of id: String) -> Int? { positions[id] }
}

import Foundation

/// The request above each grouped row, including folded calls and Mesh events.
struct ChatRequestNavigation {
    private let requests: TranscriptRequestIndex
    private var rowIds = Set<String>()
    private var readingRequest: [String: ActivityEntry] = [:]
    private var requestRows: [String: ActivityEntry] = [:]

    init(rows: [ChatTimelineRow]) {
        let entries = rows.compactMap { row -> ActivityEntry? in
            guard case .item(.activity(let entry)) = row else { return nil }
            return entry
        }
        requests = TranscriptRequestIndex(entries)
        var current: ActivityEntry?
        for row in rows {
            rowIds.insert(row.id)
            if case .item(.activity(let entry)) = row,
               let request = requests.request(containing: entry.id) {
                current = request
                requestRows[row.id] = request
            }
            readingRequest[row.id] = current
        }
    }

    func entry(topRowId: String?) -> ActivityEntry? {
        guard let topRowId, rowIds.contains(topRowId) else { return requests.previous(before: nil) }
        return readingRequest[topRowId]
    }

    func navigationEntry(topRowId: String?, afterJump: String?) -> ActivityEntry? {
        let current = entry(topRowId: topRowId)
        guard let current, current.id == afterJump else { return current }
        return requests.previous(before: current.id)
    }

    func request(atRow id: String) -> ActivityEntry? { requestRows[id] }
}

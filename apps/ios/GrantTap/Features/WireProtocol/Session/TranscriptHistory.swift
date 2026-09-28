import Foundation

struct TranscriptHistoryPage: Codable, Equatable {
    var cursor: String? = nil
    let hasMore: Bool
    var requestedCursor: String? = nil
}

/// A successfully recorded edit; counts describe edits, not the final Git tree.
struct RecordedFileChange: Codable, Equatable, Identifiable {
    let path: String
    let linesAdded: Int
    let linesRemoved: Int
    let diff: String
    var diffTruncated: Bool? = nil
    var id: String { path }
}

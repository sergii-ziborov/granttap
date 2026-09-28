import Foundation

struct SessionsHistoryQuery: Codable {
    var type = "sessions.history.query"
    let requestId: String
    let cursor: String?
    let limit: Int
    let createdAt: Double
}

struct SessionsHistoryPage: Decodable {
    let type: String
    let requestId: String
    let sessions: [SessionInfo]
    let nextCursor: String?
    let hasMore: Bool
    let sourceLimited: Bool?
    let resetRequired: Bool?
    let generatedAt: Double

    var isWellFormed: Bool {
        type == "sessions.history.page" && UUID(uuidString: requestId) != nil
            && sessions.count <= 40 && (nextCursor?.count ?? 0) <= 512
            && (!hasMore || nextCursor != nil)
    }
}

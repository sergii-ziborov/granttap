import Foundation

extension RelayClient {
    func requestSessionsHistoryPage(
        requestId: String, cursor: String?, completion: ((Error?) -> Void)? = nil
    ) {
        send(payload: SessionsHistoryQuery(
            requestId: requestId, cursor: cursor, limit: 40,
            createdAt: Date().timeIntervalSince1970 * 1_000
        ), ttl: 60, completion: completion)
    }
}

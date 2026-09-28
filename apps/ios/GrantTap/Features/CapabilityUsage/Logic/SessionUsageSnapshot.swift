import Foundation

/// Provider-reported usage can enrich a Task without replacing its stable identity.
struct SessionUsageSnapshot: Decodable, Sendable {
    let sessionId: String
    let agent: String
    let tokensSession: Int
    let tokensLastTurn: Int
    var model: String? = nil
    var contextTokensUsed: Int? = nil
    var contextWindow: Int? = nil

    var key: String { "\(agent)\u{1f}\(sessionId)" }

    var isValid: Bool {
        !sessionId.isEmpty && sessionId.utf8.count <= 256
            && !agent.isEmpty && agent.utf8.count <= 64
            && tokensSession >= 0 && tokensLastTurn >= 0
            && (contextTokensUsed.map { $0 >= 0 } ?? true)
            && (contextWindow.map { $0 > 0 } ?? true)
            && (model.map { $0.utf8.count <= 128 } ?? true)
    }

    func applying(to session: SessionInfo) -> SessionInfo {
        guard isValid, session.sessionId == sessionId, session.agent == agent else { return session }
        var result = session
        result.tokensSession = tokensSession
        result.tokensLastTurn = tokensLastTurn
        result.contextTokensUsed = contextTokensUsed
        result.contextWindow = contextWindow
        result.model = model ?? result.model
        return result
    }
}

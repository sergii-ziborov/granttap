import Foundation

/// Sample interactions stay in memory and never acquire a live computer route.
@MainActor
extension AppModel {
    func discardDemoDeliveries() {
        let before = deliveries.count
        deliveries.removeAll {
            $0.id == "demo-photo-delivery" || Self.isGrantTapDemoSessionId($0.sessionId ?? "")
        }
        if before != deliveries.count { persistDeliveries() }
    }

    func handleDemoDecision(_ request: ApprovalRequest, decision: String) -> Bool {
        guard demoMode, !demoSessionScope.isEmpty else { return false }
        guard ["allow", "deny"].contains(decision),
              let session = request.sessionId,
              demoSessionScope.contains(session),
              pending.contains(where: { $0.requestId == request.requestId && $0.sessionId == session })
        else { return true }
        pending.removeAll { $0.requestId == request.requestId }
        appendDemoEntry(session: session, kind: "status",
            text: "\(L(decision == "allow" ? "Allow" : "Deny")) · "
                + L("Demo decision saved. No command was executed."))
        return true
    }

    func handleDemoMessage(_ text: String, sessionId: String?, requestId: String?) -> Bool {
        guard demoMode, !demoSessionScope.isEmpty else { return false }
        let question = requestId.flatMap { id in questions.first { $0.requestId == id } }
        let session = sessionId ?? question?.sessionId ?? AppModelDemoFixtures.codexSessionId
        guard demoSessionScope.contains(session),
              sessions.contains(where: { $0.sessionId == session }),
              requestId == nil || question?.sessionId == session else { return true }
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8_000))
        guard !trimmed.isEmpty else { return true }
        appendDemoEntry(session: session, kind: "user", text: trimmed)
        appendDemoEntry(session: session, kind: "message",
            text: L("Demo reply received. No message was sent to a computer."))
        if let requestId { questions.removeAll { $0.requestId == requestId } }
        return true
    }

    private func appendDemoEntry(session: String, kind: String, text: String) {
        appendLocalChatEntry(sessionId: session,
            agent: sessions.first(where: { $0.sessionId == session })?.agent ?? "codex",
            entry: ActivityEntry(id: "demo-\(UUID().uuidString)", kind: kind, text: text,
                createdAt: Date().timeIntervalSince1970 * 1_000))
    }
}

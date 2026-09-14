import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func decide(_ req: ApprovalRequest, _ decision: String, by: String = "phone") {
        // Only explicit Allow/Deny (or notification action) may clear a live gate.
        // Card-body taps / navigation must never call this.
        guard approvalDecisionsInFlight[req.requestId] == nil else { return }
        markDecisionInFlight(req.requestId, decision: decision, sessionId: req.sessionId)
        pushToWatch()
        deliverDecision(requestId: req.requestId, decision: decision, by: by,
                        sessionId: req.sessionId, title: req.title,
                        agent: req.agent)
    }

    func deliverDecision(requestId: String, decision: String, by: String,
                                 sessionId: String?, title: String, agent: String) {
        guard let client = relayForRequest(requestId) else {
            finishDecisionDelivery(requestId: requestId, decision: decision, by: by,
                                   title: title, agent: agent,
                                   error: RelaySendError.disconnected)
            return
        }
        client.sendDecision(requestId: requestId, decision: decision, by: by,
                            sessionId: sessionId) { [weak self] error in
            DispatchQueue.main.async {
                self?.finishDecisionDelivery(requestId: requestId, decision: decision,
                                             by: by, title: title, agent: agent,
                                             error: error)
            }
        }
    }

    func finishDecisionDelivery(requestId: String, decision: String, by: String,
                                        title: String, agent: String, error: Error?) {
        if let error {
            clearDecisionInFlight(requestId)
            append("decision.send failed \(requestId.prefix(8)): \(error.localizedDescription)")
            AuditStore.shared.record("decision", detail: "\(decision) · \(agent) · \(by)",
                                     outcome: "failed")
            pushToWatch()
            return
        }
        // A successful WebSocket write is not proof that the native gate applied
        // the decision. Keep the card disabled until approval.resolved/cancel.
        append("\(decision) sent: \(title) (waiting for computer, \(by))")
        AuditStore.shared.record("decision", detail: "\(decision) · \(agent) · \(by)")
        pushToWatch()
    }

    /// Resolve by id — used by the notification action handler (watch tap).
    func decideById(_ requestId: String, _ decision: String, by: String,
                    roomId: String? = nil, sessionId: String? = nil) {
        if let roomId {
            if let mapped = requestSourceRoom[requestId], mapped != roomId {
                append("notification room mismatch ignored: \(requestId)")
                return
            }
            rememberRequestSourceRoom(roomId, requestId: requestId)
        }
        if let req = pending.first(where: { $0.requestId == requestId }) {
            guard Self.normalizedApprovalSession(req.sessionId)
                    == Self.normalizedApprovalSession(sessionId) else {
                append("decision session mismatch ignored: \(requestId)")
                return
            }
            decide(req, decision, by: by)
        } else {
            guard approvalDecisionsInFlight[requestId] == nil else { return }
            markDecisionInFlight(requestId, decision: decision, sessionId: sessionId)
            pushToWatch()
            deliverDecision(requestId: requestId, decision: decision, by: by,
                            sessionId: sessionId, title: requestId, agent: "unknown")
        }
    }

    /// Yes/No for MCP `ask_yes_no` / open questions (correlated user.message).
    /// Approval cards use approval.decision; plain MCP questions use only the
    /// correlated user.message reply. Mixing both paths can resolve a different
    /// waiter and leaves the phone waiting for an approval.resolved that will
    /// never exist.
    func answerQuestion(_ requestId: String, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let question = questions.first { $0.requestId == requestId }
        let request = pending.first { $0.requestId == requestId }
        let sessionId = request?.sessionId ?? question?.sessionId
        let decision: String? =
            (trimmed == "yes" || trimmed == "y" || trimmed == "да") ? "allow"
            : (trimmed == "no" || trimmed == "n" || trimmed == "нет") ? "deny" : nil

        // An exact pending ApprovalRequest owns the Allow/Deny lifecycle. Do
        // not also enqueue a user.message for the same tap.
        if let decision, let req = request {
            decide(req, decision, by: "phone")
            return
        }

        // Open MCP questions (including a textual "yes"/"no") are correlated
        // replies, not permissions. Keep the question visible until the Mac
        // acknowledges the delivery receipt so an offline room cannot eat it.
        sendMessage(text, agent: nil, cwd: nil, sessionId: sessionId, requestId: requestId)
    }

    /// Formerly routed ask_yes_no to Yes+Reply hybrid UI. That path sent
    /// user.message without reliably unblocking Cursor beforeShellExecution
    /// (ONE_TAP break: phone Yes, Mac Allows stuck). All approval.request
    /// cards use Allow/Deny → approval.decision.
    /// GrantTap MCP ask cards only. Provider permission cards use Allow/Deny.
    func isMcpAskApproval(_ req: ApprovalRequest) -> Bool {
        let agent = AgentIdentity.normalize(req.agent)
        if AgentIdentity.knownIds.contains(agent) {
            return false
        }
        let tool = req.tool.lowercased()
        return tool == "ask_yes_no" || tool == "ask" || agent == "granttap"
    }

    /// Open-text MCP `ask` may show Reply. `ask_yes_no` is Yes/No only.
    func isMcpOpenAsk(_ req: ApprovalRequest) -> Bool {
        req.tool.lowercased() == "ask"
    }

    func append(_ line: String) {
        log.insert(line, at: 0)
        if log.count > 100 { log.removeLast() }
    }
}

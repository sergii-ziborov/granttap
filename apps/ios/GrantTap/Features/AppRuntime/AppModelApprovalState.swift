import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func receive(_ req: ApprovalRequest, fromRoom room: String? = nil) {
        if let mapped = requestSourceRoom[req.requestId], let room, mapped != room {
            append("approval room collision ignored: \(req.requestId)")
            return
        }
        if wasApprovalTerminal(req.requestId, room: room, sessionId: req.sessionId) {
            append("approval terminal redelivery ignored: \(req.requestId)")
            NotificationManager.shared.clear(req.requestId)
            return
        }
        if let room { rememberRequestSourceRoom(room, requestId: req.requestId) }
        if let inFlightSession = approvalDecisionSessionScope[req.requestId],
           Self.normalizedApprovalSession(inFlightSession)
                != Self.normalizedApprovalSession(req.sessionId) {
            append("approval in-flight session collision ignored: \(req.requestId)")
            return
        }

        // LATE_BLOCKED: Mac already cancelled this id (or cancel-all) — silent, no wake/ping.
        if let cancelledAt = recentlyCancelledIds[cancellationKey(req.requestId, room: room)],
           Date().timeIntervalSince(cancelledAt) < 120 {
            append("LATE_BLOCKED: \(req.requestId)")
            NotificationManager.shared.clear(req.requestId)
            return
        }
        if let cancelAllAt = lastCancelAllAtByRoom[room ?? "legacy"],
           Date().timeIntervalSince(cancelAllAt) < 90,
           req.createdAt / 1000 < cancelAllAt.timeIntervalSince1970 + 1 {
            append("LATE_BLOCKED cancel-all: \(req.requestId)")
            NotificationManager.shared.clear(req.requestId)
            return
        }

        // Only an exact requestId is a redelivery. Similar titles can be distinct
        // gates, including gates from different chats or computers.
        if let index = pending.firstIndex(where: { $0.requestId == req.requestId }) {
            guard Self.normalizedApprovalSession(pending[index].sessionId)
                    == Self.normalizedApprovalSession(req.sessionId) else {
                append("approval session collision ignored: \(req.requestId)")
                return
            }
            pending[index] = req
            append("PING_DEDUPE same-id: \(req.requestId)")
            pushToWatch()
            return
        }
        pending.insert(req, at: 0)
        // MCP ask_yes_no also sends agent.event kind=question with the same id —
        // drop the duplicate question card so Allow/Deny is the single UI.
        questions.removeAll { $0.requestId == req.requestId }
        append("ask: \(req.agent) — \(req.title)")
        // Raise an actionable notification so the Approve/Deny buttons appear —
        // and mirror to Apple Watch — even when the app isn't frontmost.
        NotificationManager.shared.present(req, roomId: room)
        AuditStore.shared.record("approval", detail: "Received \(req.agent) approval request")
        pushToWatch()
    }

    /// Legacy mirrored decisions are not completion acknowledgements. Waiting UI
    /// is cleared only by approval.resolved / approval.cancel.
    func receiveRemoteDecision(_ dec: ApprovalDecision, fromRoom room: String? = nil) {
        let roomLabel = room.map { String($0.prefix(8)) } ?? "-"
        append("legacy decision observed: \(dec.requestId) (\(roomLabel))")
    }

    func receive(_ resolved: ApprovalResolved, fromRoom room: String) {
        guard requestBelongsToSource(resolved.requestId, room: room) else {
            append("resolved room mismatch ignored: \(resolved.requestId)")
            return
        }
        let currentSession = pending.first(where: { $0.requestId == resolved.requestId })?.sessionId
            ?? questions.first(where: { $0.requestId == resolved.requestId })?.sessionId
            ?? approvalDecisionSessionScope[resolved.requestId]
        if let expectedSession = Self.normalizedApprovalSession(currentSession),
           Self.normalizedApprovalSession(resolved.sessionId) != expectedSession {
            append("resolved session mismatch ignored: \(resolved.requestId)")
            return
        }
        markApprovalTerminal(resolved.requestId, room: room,
                             sessionId: resolved.sessionId ?? currentSession)
        let hadCard = pending.contains { $0.requestId == resolved.requestId }
            || questions.contains { $0.requestId == resolved.requestId }
            || approvalDecisionsInFlight[resolved.requestId] != nil
        pending.removeAll { $0.requestId == resolved.requestId }
        questions.removeAll { $0.requestId == resolved.requestId }
        clearDecisionInFlight(resolved.requestId)
        if focusedApprovalId == resolved.requestId { focusedApprovalId = nil }
        forgetRequestSourceRoom(resolved.requestId)
        NotificationManager.shared.clear(resolved.requestId)
        if hadCard {
            let outcome = resolved.status == "applied"
                ? "applied"
                : (resolved.note ?? resolved.status)
            append("resolved: \(resolved.requestId) \(resolved.decision ?? "terminal") (\(outcome))")
            pushToWatch()
        }
    }

    func receive(_ status: ApprovalsStatus, fromRoom room: String) {
        // Only the new explicit-coverage shape participates in ordering. A
        // legacy partial snapshot must not poison the persisted watermark.
        if status.covered != nil,
           !acceptApprovalStatusWatermark(status.generatedAt, room: room) { return }
        var incomingScopes = Set<String>()
        for request in status.pending {
            if let mapped = requestSourceRoom[request.requestId], mapped != room {
                append("status room collision ignored: \(request.requestId)")
                continue
            }
            if let index = pending.firstIndex(where: { $0.requestId == request.requestId }) {
                guard Self.normalizedApprovalSession(pending[index].sessionId)
                        == Self.normalizedApprovalSession(request.sessionId) else {
                    append("status session collision ignored: \(request.requestId)")
                    continue
                }
                pending[index] = request
                if requestSourceRoom[request.requestId] == nil {
                    rememberRequestSourceRoom(room, requestId: request.requestId)
                }
                incomingScopes.insert(Self.approvalScopeKey(
                    request.requestId, sessionId: request.sessionId
                ))
                continue
            }
            receive(request, fromRoom: room)
            if pending.contains(where: {
                $0.requestId == request.requestId
                    && Self.normalizedApprovalSession($0.sessionId)
                        == Self.normalizedApprovalSession(request.sessionId)
            }) {
                incomingScopes.insert(Self.approvalScopeKey(
                    request.requestId, sessionId: request.sessionId
                ))
            }
        }

        // Missing coverage is legacy/partial: merge pending cards only. `complete`
        // is deliberately not trusted because older producers could not account
        // for approvals emitted by another process.
        guard let covered = status.covered else { return }
        let coveredScopes = Set(covered.map {
            Self.approvalScopeKey($0.requestId, sessionId: $0.sessionId)
        })

        // Authority is exact and session-scoped. An unregistered producer's id
        // is absent from coveredScopes and therefore can never be wiped here.
        let staleRequests = pending.filter { request in
            let scope = Self.approvalScopeKey(request.requestId,
                                              sessionId: request.sessionId)
            guard requestSourceRoom[request.requestId] == room,
                  request.createdAt <= status.generatedAt,
                  coveredScopes.contains(scope),
                  !incomingScopes.contains(scope) else { return false }
            return true
        }
        guard !staleRequests.isEmpty else { return }
        let stale = Set(staleRequests.map(\.requestId))
        for request in staleRequests {
            markApprovalTerminal(request.requestId, room: room,
                                 sessionId: request.sessionId)
        }
        pending.removeAll { stale.contains($0.requestId) }
        questions.removeAll { $0.requestId.map(stale.contains) ?? false }
        for id in stale {
            clearDecisionInFlight(id)
            forgetRequestSourceRoom(id)
            NotificationManager.shared.clear(id)
        }
        if focusedApprovalId.map(stale.contains) == true { focusedApprovalId = nil }
        append("approvals.status removed \(stale.count) stale approval card(s)")
        pushToWatch()
    }

    func receive(_ cancel: ApprovalCancel, fromRoom room: String? = nil) {
        if cancel.cancelAll == true {
            clearAllPendingApprovals(reason: cancel.reason ?? "mac", fromRoom: room)
            return
        }
        guard let id = cancel.requestId, !id.isEmpty else { return }
        guard requestBelongsToSource(id, room: room) else {
            append("cancel room mismatch ignored: \(id)")
            return
        }
        let currentSession = pending.first(where: { $0.requestId == id })?.sessionId
            ?? questions.first(where: { $0.requestId == id })?.sessionId
            ?? approvalDecisionSessionScope[id]
        markApprovalTerminal(id, room: room, sessionId: currentSession)
        recentlyCancelledIds[cancellationKey(id, room: room)] = Date()
        pending.removeAll { $0.requestId == id }
        questions.removeAll { $0.requestId == id }
        clearDecisionInFlight(id)
        if focusedApprovalId == id { focusedApprovalId = nil }
        forgetRequestSourceRoom(id)
        NotificationManager.shared.clear(id)
        append("cancel: \(id) (\(cancel.reason ?? "mac"))")
        pushToWatch()
    }

    func clearAllPendingApprovals(reason: String, fromRoom room: String?) {
        let ids = Set((pending.map(\.requestId) + questions.compactMap(\.requestId)).filter { id in
            guard let room else { return true }
            return requestSourceRoom[id] == room
        })
        for id in ids {
            let currentSession = pending.first(where: { $0.requestId == id })?.sessionId
                ?? questions.first(where: { $0.requestId == id })?.sessionId
                ?? approvalDecisionSessionScope[id]
            markApprovalTerminal(id, room: room, sessionId: currentSession)
            recentlyCancelledIds[cancellationKey(id, room: room)] = Date()
            clearDecisionInFlight(id)
            forgetRequestSourceRoom(id)
        }
        lastCancelAllAtByRoom[room ?? "legacy"] = Date()
        pending.removeAll { ids.contains($0.requestId) }
        questions.removeAll { $0.requestId.map(ids.contains) ?? false }
        if focusedApprovalId.map(ids.contains) == true { focusedApprovalId = nil }
        for id in ids { NotificationManager.shared.clear(id) }
        append("cancel-all: \(reason)")
        AuditStore.shared.record("decision", detail: "cancel-all · \(reason)")
        pushToWatch()
    }

    /// Parent/MCP mirrors of Cursor shell gates — must match Mac Allow wording/UI.
    static func isShellishQuestion(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.range(of: #"^allow\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return t.range(of: "cursor shell", options: .caseInsensitive) != nil
    }
}

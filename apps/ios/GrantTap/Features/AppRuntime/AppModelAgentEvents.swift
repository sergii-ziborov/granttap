import CryptoKit
import Foundation
import SwiftUI
import UIKit

extension AppModel {
    /// Identify a relayed agent line by its content, not by `String.hashValue`.
    ///
    /// Swift seeds that hash per process, so the identical replayed event minted
    /// a different id after every relaunch and the replay guard missed it — the
    /// same answer then appeared twice in the chat.
    nonisolated static func agentEventEntryId(text: String, createdAt: Double) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
        return "agent-event-\(Int(createdAt))-\(digest)"
    }

    private func consumeCompletedOriginDelivery(_ id: String) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }) else { return }
        if let generation = deliveries[index].attemptGeneration {
            liveDeliveryAttemptGenerations.remove(generation)
        }
        let retainsImagePreview = deliveries[index].attachments.contains {
            $0.mimeType.hasPrefix("image/") && !$0.data.isEmpty
        }
        if retainsImagePreview {
            deliveries[index].state = .delivered
            deliveries[index].updatedAt = Date().timeIntervalSince1970 * 1000
            deliveries[index].error = nil
            deliveries[index].nextRetryAt = nil
            deliveries[index].processingAcknowledgedAt = nil
            deliveries[index].processingRetryStartedAt = nil
            deliveries[index].attemptGeneration = nil
        } else {
            deliveries.remove(at: index)
        }
        persistDeliveries()
    }

    private func shouldStopAgentEvent(_ event: AgentEvent, fromRoom room: String?) -> Bool {
        if let room, let sessionId = event.sessionId {
            rememberSessionSourceRoom(room, sessionId: sessionId)
        }
        if let id = event.requestId, let room {
            if let mapped = requestSourceRoom[id], mapped != room {
                append("agent event room collision ignored: \(id)")
                return true
            }
            rememberRequestSourceRoom(room, requestId: id)
        }
        if event.kind == "status",
           let id = event.requestId,
           event.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "dismiss" {
            append("legacy dismiss observed: \(id)")
            return true
        }
        guard event.kind == "question", let id = event.requestId,
              !questions.contains(where: { $0.requestId == id }),
              !pending.contains(where: { $0.requestId == id }) else { return false }
        if Self.isShellishQuestion(event.text) {
            receive(ApprovalRequest(
                type: "approval.request", requestId: id, agent: "cursor",
                kind: "permission", tool: "Shell", title: event.text,
                command: nil, cwd: nil, sessionId: event.sessionId,
                risk: .medium, danger: nil, createdAt: event.createdAt
            ), fromRoom: room)
            return true
        }
        questions.insert(event, at: 0)
        NotificationManager.shared.presentQuestion(event, roomId: room)
        let remaining = max(0, event.createdAt / 1000 + 185 - Date().timeIntervalSince1970)
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self else { return }
            self.questions.removeAll { $0.requestId == id }
            self.pushToWatch()
        }
        return false
    }

    private func appendAgentEvent(
        _ event: AgentEvent,
        to chatId: String,
        terminalOriginEvent: Bool
    ) {
        let statusTerms = ["not logged in", "quota", "out of tokens", "CLI not found"]
        let kind = event.kind == "status" || statusTerms.contains(where: {
            event.text.localizedCaseInsensitiveContains($0)
        }) ? "status" : "message"
        let agent = sessions.first(where: { $0.sessionId == chatId })?.agent
            ?? sessionHistory.first(where: { $0.sessionId == chatId })?.agent
            ?? "codex"
        let stableOrigin = event.originMessageId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let entryId: String
        if terminalOriginEvent, let stableOrigin, !stableOrigin.isEmpty {
            entryId = "agent-event-response-origin-\(stableOrigin)"
        } else {
            entryId = Self.agentEventEntryId(text: event.text, createdAt: event.createdAt)
        }
        let isExactReplay = activities[chatId]?.entries.contains { $0.id == entryId } == true
        let providerAlreadyRendered = kind == "message"
            && activities[chatId]?.entries.contains { entry in
                (entry.kind == "message" || entry.kind == "final")
                    && entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        == event.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    && abs(entry.createdAt - event.createdAt) <= 5 * 60 * 1_000
                    && !entry.id.hasPrefix("agent-event-")
            } == true
        guard !isExactReplay && !providerAlreadyRendered else { return }
        appendLocalChatEntry(
            sessionId: chatId, agent: agent, entryId: entryId, kind: kind,
            text: event.text, createdAt: event.createdAt
        )
    }

    func receive(_ event: AgentEvent, fromRoom room: String? = nil) {
        if shouldStopAgentEvent(event, fromRoom: room) { return }
        // A reply in a shared chat reaches the members watching it too.
        forwardAgentEventToMembers(event, fromRoom: room)
        // Route a response only by an exact origin message or an exact session id.
        // Never adopt sessionToOpen / the first in-flight stub: those are global UI
        // hints and can belong to another chat or another computer.
        let preferredRoom = connectionRegistry.preferredId
        let sourceIsPreferred = room == nil || preferredRoom == nil || room == preferredRoom
        let sessionPayloadAccepted: Bool = {
            guard let room,
                  let sessionId = event.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sessionId.isEmpty else { return true }
            return acceptsSessionPayload(sessionId: sessionId, fromRoom: room)
        }()
        var chatId: String?
        var consumedOriginMessageId: String?
        var failedLocalOriginSessionId: String?
        let terminalOriginEvent = DeliveryOutboxPolicy.consumesOrigin(eventKind: event.kind)
        if let origin = event.originMessageId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !origin.isEmpty,
           let index = deliveries.firstIndex(where: { $0.id == origin }) {
            let delivery = deliveries[index]
            let roomMatches = room == nil || delivery.roomId == nil || delivery.roomId == room
            if roomMatches {
                if sourceIsPreferred {
                    let exactStub = delivery.sessionId.map { resolvedSessionId($0) }
                    if let realId = event.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !realId.isEmpty {
                        if let originalStub = delivery.sessionId,
                           localOnlySessionIds.contains(originalStub) {
                            if exactStub != realId {
                                remapLocalSession(from: originalStub, to: realId)
                                chatId = realId
                            } else {
                                // Echoing the phone UUID is not provider-native
                                // confirmation. Keep followers blocked until a
                                // distinct id arrives, or fail them with terminal.
                                chatId = originalStub
                                if terminalOriginEvent {
                                    failedLocalOriginSessionId = originalStub
                                }
                            }
                            if terminalOriginEvent { consumedOriginMessageId = delivery.id }
                        } else if exactStub == nil || exactStub == realId {
                            chatId = realId
                            if terminalOriginEvent { consumedOriginMessageId = delivery.id }
                        } else {
                            append("origin/session mismatch ignored: \(origin.prefix(8))")
                        }
                    } else {
                        // A startup/status event may arrive before the machine
                        // reports its real session id. Show it on the exact stub
                        // and retain it; a terminal failure has no later remap.
                        chatId = exactStub
                        if terminalOriginEvent {
                            consumedOriginMessageId = delivery.id
                            if let sessionId = delivery.sessionId,
                               localOnlySessionIds.contains(sessionId) {
                                failedLocalOriginSessionId = sessionId
                            }
                        }
                    }
                } else if terminalOriginEvent {
                    // The secondary room is not allowed to mutate the preferred
                    // catalog, but its completed delivery no longer needs retry.
                    consumedOriginMessageId = delivery.id
                    if let sessionId = delivery.sessionId,
                       localOnlySessionIds.contains(sessionId) {
                        failedLocalOriginSessionId = sessionId
                    }
                }
            } else {
                append("origin room mismatch ignored: \(origin.prefix(8))")
            }
        } else if sourceIsPreferred, sessionPayloadAccepted,
                  let exactId = event.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !exactId.isEmpty {
            // Existing-session traffic can update that session, but cannot adopt
            // any unrelated phone-minted stub.
            chatId = resolvedSessionId(exactId)
        }

        if let chatId { appendAgentEvent(event, to: chatId, terminalOriginEvent: terminalOriginEvent) }
        if let consumedOriginMessageId {
            consumeCompletedOriginDelivery(consumedOriginMessageId)
        }
        if let failedLocalOriginSessionId {
            failDeferredFollowUps(forLocalSessionId: failedLocalOriginSessionId)
        }
        append("agent: \(event.text)")
        pushToWatch()
    }

}

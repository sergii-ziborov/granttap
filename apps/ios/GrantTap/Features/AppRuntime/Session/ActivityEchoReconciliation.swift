import Foundation

extension AppModel {
    /// Replace only the optimistic row owned by the delivery that best matches
    /// each provider transcript echo. Text-only global dedupe would collapse
    /// legitimate repeated messages, so identity, route, session and time are
    /// all part of the match and every delivery can be consumed at most once.
    /// A busy chat can queue a message for the whole delivery lifetime before it
    /// reaches the transcript, so a fixed window anchored on send time misses it.
    static let echoSkewMs = 20 * 60 * 1_000.0

    /// Distance between a delivery and a transcript echo, measured from whichever
    /// of the delivery's timestamps is closest: a queued message enters the log
    /// around when it was actually delivered, not when it was sent.
    static func echoSkew(_ delivery: OutgoingDelivery, remoteAt: Double) -> Double {
        let anchors = [delivery.createdAt, delivery.updatedAt,
                       delivery.processingAcknowledgedAt].compactMap { $0 }
        return anchors.map { abs($0 - remoteAt) }.min() ?? .greatestFiniteMagnitude
    }

    static func echoMatches(_ delivery: OutgoingDelivery, remoteAt: Double) -> Bool {
        echoSkew(delivery, remoteAt: remoteAt) <= echoSkewMs
    }

    func reconcileOptimisticUserBubbles(
        existing: SessionActivity,
        incoming: SessionActivity,
        sourceNamespace: String?
    ) -> SessionActivity {
        let remoteUserEntries = incoming.entries.filter {
            ($0.kind == "user" || $0.kind == "message")
                && !$0.id.hasPrefix("local-user-")
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { $0.createdAt < $1.createdAt }
        guard !remoteUserEntries.isEmpty else { return existing }

        let resolvedIncoming = resolvedSessionId(incoming.sessionId)
        let candidateDeliveries = deliveries.filter { delivery in
            guard let sessionId = delivery.sessionId,
                  resolvedSessionId(sessionId) == resolvedIncoming else { return false }
            if let sourceNamespace, let deliveryRoom = delivery.roomId,
               sourceNamespace != deliveryRoom { return false }
            return existing.entries.contains {
                $0.id == "local-user-\(delivery.id)"
                    || $0.id.hasPrefix("local-user-\(delivery.id)-")
            }
        }
        guard !candidateDeliveries.isEmpty else { return existing }

        var consumed = Set<String>()
        for remote in remoteUserEntries {
            let text = remote.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let match = candidateDeliveries
                .filter {
                    !consumed.contains($0.id)
                        && $0.rejectedByComputer != true && $0.admissionRejected != true
                        && remote.createdAt >= ($0.manualRetryStartedAt ?? $0.transportAttemptStartedAt ?? $0.createdAt) - 1_000
                        && Self.nativeEchoTextMatches($0, text: text)
                        && Self.echoMatches($0, remoteAt: remote.createdAt)
                }
                .min {
                    Self.echoSkew($0, remoteAt: remote.createdAt)
                        < Self.echoSkew($1, remoteAt: remote.createdAt)
                }
            if let match {
                guard var local = existing.entries.first(where: { $0.id == "local-user-\(match.id)" }) else { continue }
                if local.images?.isEmpty != false { local.images = rememberSubmittedImages(match) }
                if retainImagesForNativeEcho(local: local, caption: remote, incoming: incoming) {
                    consumed.insert(match.id)
                }
            }
        }
        guard !consumed.isEmpty else { return existing }
        let retained = existing.entries.filter { entry in
            !consumed.contains { deliveryId in
                entry.id == "local-user-\(deliveryId)"
                    || entry.id.hasPrefix("local-user-\(deliveryId)-")
            }
        }
        return SessionActivity(
            type: existing.type,
            sessionId: existing.sessionId,
            agent: existing.agent,
            state: existing.state,
            entries: retained,
            generatedAt: existing.generatedAt, history: existing.history
        )
    }

    /// Provider logs eventually contain the same user/assistant lines that the
    /// phone rendered optimistically. Once the outbox row is complete, converge
    /// those two stable sources without collapsing legitimate repeated text.
    func reconcileCompletedLocalEchoes(
        existing: SessionActivity,
        incoming: SessionActivity
    ) -> SessionActivity {
        // Same reason as reconcileOptimisticUserBubbles: a queued message's echo
        // lands long after the optimistic bubble, so the window must cover the
        // delivery lifetime, not a few minutes.
        let maximumEchoSkewMs = Self.echoSkewMs
        var consumed = Set<String>()
        let activeLocalIds = Set(deliveries.map { "local-user-\($0.id)" })
        let local = existing.entries.filter { entry in
            // Every relayed agent bubble converges, not only the ones bound to
            // an origin delivery: a reply produced without one is still the same
            // line the provider log is about to show.
            if entry.id.hasPrefix("agent-event-") { return true }
            guard entry.id.hasPrefix("local-user-") else { return false }
            return !activeLocalIds.contains { activeId in
                entry.id == activeId || entry.id.hasPrefix("\(activeId)-")
            }
        }
        for remote in incoming.entries where !remote.id.hasPrefix("local-user-") {
            let remoteIsUser = remote.kind == "user"
            let remoteIsAgent = remote.kind == "message" || remote.kind == "final"
            guard remoteIsUser || remoteIsAgent else { continue }
            let text = remote.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let match = local.filter { candidate in
                guard !consumed.contains(candidate.id),
                      candidate.text.trimmingCharacters(in: .whitespacesAndNewlines) == text else {
                    return false
                }
                if remoteIsUser {
                    // A repeated user line is legitimate, so keep the time bound
                    // that stops two identical sends collapsing into one.
                    return candidate.id.hasPrefix("local-user-")
                        && abs(candidate.createdAt - remote.createdAt) <= maximumEchoSkewMs
                }
                // The transcript is the source of truth for an answer. The bridge
                // durably replays a short reply like "ok", and its matching
                // transcript row can scroll out of the bounded window, so a time
                // bound leaves the relayed copy stranded as a permanent duplicate.
                // Same text in the same chat is enough to converge them.
                return candidate.id.hasPrefix("agent-event-")
            }.min {
                abs($0.createdAt - remote.createdAt) < abs($1.createdAt - remote.createdAt)
            }
            if let match, retainImagesForNativeEcho(local: match, caption: remote, incoming: incoming) {
                consumed.insert(match.id)
            }
        }
        guard !consumed.isEmpty else { return existing }
        return SessionActivity(
            type: existing.type,
            sessionId: existing.sessionId,
            agent: existing.agent,
            state: existing.state,
            entries: existing.entries.filter { !consumed.contains($0.id) },
            generatedAt: existing.generatedAt, history: existing.history
        )
    }

    /// Local optimistic / agent.event chat lines — must mutate via full dict
    /// reassignment so SwiftUI refreshes (same static-chat bug as applyActivity).
}

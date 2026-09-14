import Foundation

extension DeliveryPersistence {
    static func compactAdmissionFailure(
        from delivery: OutgoingDelivery,
        maxEncodedRowBytes: Int
    ) -> OutgoingDelivery {
        let identifier = boundedUTF8(delivery.id, maxBytes: 96)
        let fullError = L("Message was not sent because the reliable outbox is full or the message is too large.")

        func make(
            text: String,
            sessionId: String?,
            requestId: String?,
            roomId: String?,
            error: String
        ) -> OutgoingDelivery {
            OutgoingDelivery(
                id: identifier,
                text: text,
                agent: nil,
                cwd: nil,
                sessionId: sessionId,
                requestId: requestId,
                roomId: roomId,
                attachments: [],
                preferredMcp: nil,
                skill: nil,
                createdAt: delivery.createdAt,
                updatedAt: delivery.updatedAt,
                attempts: 0,
                state: .failed,
                error: error,
                nextRetryAt: nil,
                processingAcknowledgedAt: nil,
                processingRetryStartedAt: nil,
                admissionRejected: true,
                attemptGeneration: nil
            )
        }

        // Every untrusted string is UTF-8 byte-bounded before encoding. The
        // exact encoded row is then measured against the bytes still available
        // beside protected active rows; progressively smaller fallbacks retain
        // an explicit failure even for escape-heavy input.
        let candidates = [
            make(
                text: boundedUTF8(delivery.text, maxBytes: 256),
                sessionId: delivery.sessionId.map { boundedUTF8($0, maxBytes: 256) },
                requestId: delivery.requestId.map { boundedUTF8($0, maxBytes: 256) },
                roomId: delivery.roomId.map { boundedUTF8($0, maxBytes: 256) },
                error: boundedUTF8(fullError, maxBytes: 512)
            ),
            make(
                text: "",
                sessionId: delivery.sessionId.map { boundedUTF8($0, maxBytes: 128) },
                requestId: nil,
                roomId: nil,
                error: boundedUTF8(fullError, maxBytes: 192)
            ),
            make(
                text: "",
                sessionId: nil,
                requestId: nil,
                roomId: nil,
                error: "Outbox admission rejected."
            )
        ]
        let encoder = JSONEncoder()
        return candidates.first(where: {
            guard let row = try? encoder.encode($0) else { return false }
            return row.count <= max(0, maxEncodedRowBytes)
        }) ?? candidates[candidates.count - 1]
    }

    static func boundedUTF8(_ value: String, maxBytes: Int) -> String {
        let budget = max(0, maxBytes)
        guard value.utf8.count > budget else { return value }
        var result = ""
        var used = 0
        for scalar in value.unicodeScalars {
            let fragment = String(scalar)
            let bytes = fragment.utf8.count
            guard bytes <= budget - used else { break }
            result.append(contentsOf: fragment)
            used += bytes
        }
        return result
    }

    static func appendingTerminalRows(
        required: [OutgoingDelivery],
        optional: [OutgoingDelivery],
        maxCount: Int,
        maxEncodedBytes: Int
    ) -> [OutgoingDelivery] {
        let countBudget = max(0, maxCount)
        let byteBudget = max(0, maxEncodedBytes)
        guard required.count <= countBudget,
              let requiredData = encodedData(required),
              requiredData.count <= byteBudget else {
            // Active rows and the newest explicit failure are never silently
            // discarded. `save` will refuse an impossible over-budget set.
            return required
        }
        let encoder = JSONEncoder()
        var kept = required
        var encodedBytes = requiredData.count
        for delivery in optional where kept.count < countBudget {
            guard let row = try? encoder.encode(delivery) else { continue }
            let addedBytes = row.count + (kept.isEmpty ? 0 : 1)
            guard addedBytes <= byteBudget,
                  encodedBytes <= byteBudget - addedBytes else { continue }
            kept.append(delivery)
            encodedBytes += addedBytes
        }
        return kept
    }
}

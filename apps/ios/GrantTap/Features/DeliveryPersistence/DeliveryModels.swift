import Foundation

enum DeliveryState: String, Codable {
    case queued, sending, delivered, failed
}

struct OutgoingDelivery: Codable, Identifiable {
    let id: String
    let text: String
    let agent: String?
    let cwd: String?
    let sessionId: String?
    let requestId: String?
    /// Authenticated relay room selected when the message was created.
    /// Optional only so pre-room-pinning persisted rows can migrate safely.
    var roomId: String? = nil
    /// Project this new chat was opened from. Follow-ups and home compose omit it.
    var projectId: String? = nil
    var attachments: [UserAttachment]
    /// Attachments that went ahead of this message; sent by id while they
    /// stand, sent inline again when the computer says one never came.
    var attachmentRefs: [UserAttachmentRef]? = nil
    let preferredMcp: String?
    let skill: String?
    /// Chosen for this turn; nil keeps whatever the chat already uses. Optional
    /// so rows persisted before the choice existed still decode.
    var model: String? = nil
    var permissionMode: String? = nil
    var effort: String? = nil
    let createdAt: Double
    var updatedAt: Double
    var attempts: Int
    var state: DeliveryState
    var error: String?
    var nextRetryAt: Double?
    /// Local receipt time for the machine's non-terminal processing ack.
    /// Persisted so an app restart does not resend while the provider is still
    /// allowed to use its full execution timeout.
    var processingAcknowledgedAt: Double? = nil
    /// The processing-timeout retry is allowed once. Its local start time both
    /// records that the retry budget was consumed and bounds final retention.
    var processingRetryStartedAt: Double? = nil
    /// Admission failures are compact persisted UI rows, never retryable
    /// payloads: their original attachments intentionally were not retained.
    var admissionRejected: Bool? = nil
    /// Per-WebSocket-send generation. A late completion from an older send must
    /// never consume the retry budget or overwrite a newer receipt/state.
    var attemptGeneration: String? = nil
    /// A follow-up composed against a phone-minted stub cannot be sent until the
    /// originating new task reports its provider-native session id. Persist this
    /// so relaunch/reconnect never turns that follow-up into a second new task.
    var awaitingSessionRemap: Bool? = nil
}

enum DeliveryOutboxPolicy {
    /// Mirrors bridge `deliverToSession` / `startNewTask` timeout (240 seconds).
    static let providerTimeoutMs: Double = 240_000
    /// The bridge's durable `processing` lease is deliberately longer than the
    /// provider call. Reusing a message id before it expires only deduplicates.
    static let machineProcessingLeaseMs: Double = 300_000
    /// Relay/event propagation and app wake margin after provider completion.
    static let terminalEventMarginMs: Double = 30_000
    static let processingRetryDelayMs = machineProcessingLeaseMs + terminalEventMarginMs
    static let terminalAttemptWindowMs = providerTimeoutMs + terminalEventMarginMs
    static let terminalLifecycleMs = processingRetryDelayMs + terminalAttemptWindowMs
    static let unacknowledgedRetentionMs: Double = 120_000
    static let failedVisibilityMs: Double = 120_000
    static let maximumLocalRetentionMs = terminalLifecycleMs + failedVisibilityMs
    static let sentImagePreviewRetentionMs: Double = 24 * 60 * 60 * 1_000
    static let userMessageRelayTTLSeconds = unacknowledgedRetentionMs / 1_000

    static func terminalDeadline(for delivery: OutgoingDelivery) -> Double? {
        if let retryStartedAt = delivery.processingRetryStartedAt {
            return retryStartedAt + terminalAttemptWindowMs
        }
        // Preserve one full second-attempt window after the first attempt's
        // timeout. A suspended app may reconcile the persisted retry late.
        return delivery.processingAcknowledgedAt.map {
            $0 + processingRetryDelayMs + terminalAttemptWindowMs
        }
    }

    static func consumesOrigin(eventKind: String?) -> Bool {
        // Older monitors omitted `kind` for final answers. Explicit status and
        // question events are progress, never terminal delivery evidence.
        eventKind == "response" || eventKind == nil
    }
}

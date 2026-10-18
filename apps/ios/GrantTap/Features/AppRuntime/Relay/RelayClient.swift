import CryptoKit
import Foundation

/// Phone-side relay client. Mirrors packages/core/relay-client.ts:
/// connects over WebSocket, seals/opens payloads with the pairing keys, and
/// surfaces decoded ApprovalRequests. The relay only ever sees ciphertext.
final class RelayClient: NSObject, URLSessionWebSocketDelegate {
    let pairing: Pairing
    let relaySubmissions = RelaySubmissionTracker()
    var sessionKeys: [String: String]

    /// Session controls can be tapped before the monitor has returned the
    /// independent task key. Keep only a small, room-bound in-memory backlog;
    /// plaintext is never persisted and each entry is revalidated before send.
    enum SessionPayloadCoalescingKey: Hashable {
        case access
        case mcp(String)
        case skill(String)
        case shell
        case compact
        case control
        case projectPolicy
        case unique(UUID)
    }

    struct PendingSessionQueueKey: Hashable {
        let room: String
        let sessionId: String
        let payload: SessionPayloadCoalescingKey
    }

    struct PendingSessionPayload {
        let id: UUID
        let queueKey: PendingSessionQueueKey
        let plain: Data
        let expiresAt: TimeInterval?
        let deliveryId: String
        let completion: ((Error?) -> Void)?
    }

    let sessionStateLock = NSLock()
    var pendingSessionPayloads: [PendingSessionQueueKey: PendingSessionPayload] = [:]
    /// Includes in-flight generations so a failed older control cannot be
    /// requeued over a newer coalesced value.
    var latestSessionPayloadIds: [PendingSessionQueueKey: UUID] = [:]
    var sessionSubscriptionRetryTokens: [String: UUID] = [:]
    var sessionSubscriptionRetryAttempts: [String: Int] = [:]
    static let maxPendingSessionPayloads = 64
    static let maxPendingSessionPayloadSize = 64 * 1_024
    var task: URLSessionWebSocketTask?
    var endpointLookup: Task<Void, Never>?
    var endpointPolling: Task<Void, Never>?
    var resolvedRelayURL: String?
    lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    /// Reconnection: without this a single relay hiccup left the app showing
    /// "офлайн" until it was restarted by hand.
    var wantsConnection = false
    var initialConnectionStartedAt: TimeInterval?
    var retryDelay: TimeInterval = 1
    var socketOpenedAt: TimeInterval?
    let maxRetryDelay: TimeInterval = 15
    var reconnectScheduled = false
    var reconnectGeneration: UUID?
    /// A stale catalog means the peer's outbound half may also be dead.
    /// Carry this once on the next authenticated hello.
    var recoverPeerOnNextHello = false
    /// The relay may retry a reliable envelope until its acknowledgement
    /// arrives. Bind replay detection to authenticated ciphertext rather than
    /// the relay-controlled delivery id, and keep the cache bounded.
    var seenCiphertexts: Set<String> = []
    var seenCiphertextOrder: [String] = []
    static let maxSeenCiphertexts = 2_048

    /// Called on the main actor when a new approval request arrives.
    var onRequest: ((ApprovalRequest) -> Void)?
    /// Machine → phone: clear a pending Allow (Cursor already approved / orphan).
    var onDecision: ((ApprovalDecision) -> Void)?
    var onApprovalCancel: ((ApprovalCancel) -> Void)?
    var onApprovalResolved: ((ApprovalResolved) -> Void)?
    var onApprovalsStatus: ((ApprovalsStatus) -> Void)?
    var onAgentEvent: ((AgentEvent) -> Void)?
    var onSessions: ((SessionsStatus) -> Void)?
    var onConfigCommandResult: ((ConfigCommandResult) -> Void)?
    var latestConfigEpoch: String?
    var onSessionsHistoryPage: ((SessionsHistoryPage) -> Void)?
    var onActivity: ((SessionActivity) -> Void)?
    var onImageChunk: ((SessionImageChunk) -> Void)?
    var onWorkspaceResult: ((TaskWorkspaceSnapshot) -> Void)?
    var onCapabilityUsage: ((CapabilityUsageStatus) -> Void)?
    var onCapabilityCatalog: ((CapabilityCatalogStatus) -> Void)?
    var onCompactResult: ((SessionCompactResult) -> Void)?
    var onTaskTransferContinueResult: ((TaskTransferContinueResult) -> Void)?
    var onProjectTransportAck: ((ProjectTransportAck) -> Void)?
    var onSessionControlResult: ((SessionControlResult) -> Void)?
    var onProviderHookTrustResult: ((ProviderHookTrustResult) -> Void)?
    var onToolUpdateResult: ((ToolUpdateResult) -> Void)?
    var onMeshEvent: ((ProjectMeshEvent) -> Void)?
    var onMeshSnapshot: ((ProjectMeshSnapshot) -> Void)?
    var onInvocationPage: ((ProjectInvocationPage) -> Void)?
    var onProjectPolicyStatus: ((ProjectPolicyStatus) -> Void)?
    var onProjectPolicyAck: ((ProjectPolicyAck) -> Void)?
    var onProjectPolicyRejected: ((ProjectPolicyRejected) -> Void)?
    /// A computer's, or a Project owner's, answer to a claim release from here.
    var onClaimReleaseResult: ((MeshClaimReleaseResult) -> Void)?
    var onDeliveryReceipt: ((DeliveryReceipt) -> Void)?
    var onControllerPairOffer: ((ControllerPairOffer) -> Void)?
    var onKnowledgeWriteResult: ((KnowledgeWriteResult) -> Void)?
    /// Machine → phone: "I am alive", independent of how slow the catalog is.
    var onMachineHeartbeat: ((MachineHeartbeat) -> Void)?
    /// Machine → phone: who is making this computer work right now.
    var onMachineLoad: ((MachineLoad) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    #if DEBUG
    var wireDiagnosticCounts: [String: Int] = [:]
    var wireDiagnosticReportedAt: TimeInterval = 0
    var onWireDiagnosticChange: (() -> Void)?
    #endif

    /// Which side of the room this client is. A phone paired with a computer
    /// is the phone; a phone that invited another phone speaks to it as the
    /// computer would, so the other phone needs nothing new.
    var role: Role { pairing.role == "machine" ? .machine : .phone }
    var peerRole: Role { role == .machine ? .phone : .machine }
    /// Machine side only: every payload the other phone sends, by type, for
    /// the owner's rules to act on.
    var onHubPayload: ((String, Data) -> Void)?

    init(pairing: Pairing) {
        self.pairing = pairing
        self.sessionKeys = SessionKeyVault.load(room: pairing.room)
    }

    /// Debug evidence contains counters only, never packet contents or keys.
    func noteWireDiagnostic(_ stage: String) {
        #if DEBUG
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.wireDiagnosticCounts[stage, default: 0] += 1
            let now = Date().timeIntervalSince1970
            guard now - self.wireDiagnosticReportedAt >= 1 else { return }
            self.wireDiagnosticReportedAt = now
            self.onWireDiagnosticChange?()
        }
        #endif
    }

    func connect() {
        if !wantsConnection { initialConnectionStartedAt = Date().timeIntervalSince1970 }
        wantsConnection = true
        startEndpointPolling()
        openSocket()
    }

    /// Give the saved authenticated route its first handshake before rekeying.
    /// Repeated reconnects cannot extend this bounded startup window.
    func awaitingInitialPeer(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard wantsConnection, let started = initialConnectionStartedAt else { return false }
        return now >= started && now - started < 30
    }

    func openResolvedSocket(_ address: String) {
        // Room in the URL — the Cloudflare relay routes to a Durable Object
        // before the upgrade; the Node dev relay ignores the parameter.
        // Empty path → /ws so vault HTML on GET `/` cannot steal the upgrade
        // (HTTP 200 Unlock page → phone never receives sessions.status).
        guard wantsConnection,
              var comps = URLComponents(string: address) else { return }
        let path = comps.path
        if path.isEmpty || path == "/" {
            comps.path = "/ws"
        }
        var items = comps.queryItems ?? []
        if !items.contains(where: { $0.name == "room" }) {
            items.append(URLQueryItem(name: "room", value: pairing.room))
        }
        comps.queryItems = items
        guard let url = comps.url else { return }
        cancelScheduledReconnect()
        interruptSocketForReplacement()
        resolvedRelayURL = address
        var request = URLRequest(url: url)
        request.setValue("1", forHTTPHeaderField: "X-GrantTap-Recipient-Routing")
        request.setValue(CiphertextRecipient.identifier(publicKey: pairing.myPublicKey),
                         forHTTPHeaderField: "X-GrantTap-Recipient-Key-Id")
        if let pushAuth = pairing.pushAuth, !pushAuth.isEmpty {
            request.setValue("Bearer \(pushAuth)", forHTTPHeaderField: "Authorization")
        }
        let t = session.webSocketTask(with: request)
        t.maximumMessageSize = 22_010_000
        task = t
        t.resume()
        receiveLoop(t)
    }

    func disconnect() {
        relaySubmissions.disconnect()
        wantsConnection = false
        cancelScheduledReconnect()
        initialConnectionStartedAt = nil
        endpointLookup?.cancel()
        endpointPolling?.cancel()
        endpointPolling = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onConnectionChange?(false)
    }

    /// Drop and reopen the WebSocket so a stale link recovers on pull-to-refresh.
    func forceReconnect(requestPeerRecovery: Bool = false) {
        recoverPeerOnNextHello = recoverPeerOnNextHello || requestPeerRecovery
        guard wantsConnection else {
            connect()
            return
        }
        openSocket()
    }

    /// `didClose` for a replaced task is ignored by the identity guard below,
    /// so emit exactly one down edge before replacement. AppModel uses it to
    /// invalidate outbox send generations whose completion may never arrive.
    func interruptSocketForReplacement() {
        relaySubmissions.disconnect()
        guard let current = task else { return }
        current.cancel(with: .goingAway, reason: nil)
        task = nil
        onConnectionChange?(false)
    }

    var lastWakeAt: TimeInterval = 0

    /// A remote notification means the relay has an encrypted envelope waiting.
    /// Reopening the socket flushes it even when iOS suspended the old connection.
    func wakeForRemoteNotification() {
        guard wantsConnection else { connect(); return }
        let now = Date().timeIntervalSince1970
        // APNs bursts were cancelling a healthy socket every second → Connected flicker.
        if task != nil, now - lastWakeAt < 4 { return }
        lastWakeAt = now
        openSocket()
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            guard self.task === webSocketTask else { return }
            // The backoff resets only once this connection has stayed up.
            self.noteSocketOpened()
            self.onConnectionChange?(true)
            let recoverPeer = self.recoverPeerOnNextHello
            self.recoverPeerOnNextHello = false
            self.sendHello(recoverPeer: recoverPeer)
            // A subscribe may have raced a disconnect, and a key grant may
            // already be cached. Resume both cases after every socket open.
            self.resumePendingSessionPayloads()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            guard self.task === webSocketTask else { return }
            self.task = nil
            self.noteSocketClosed(closeCode: closeCode.rawValue, reason: reason)
            self.onConnectionChange?(false)
            self.scheduleReconnect()
        }
    }
}

enum RelaySendError: LocalizedError {
    case disconnected, encoding, encryption, missingSessionKey
    case invalidSessionScope, sessionQueueFull, sessionPayloadTooLarge
    case sessionPayloadExpired, supersededSessionPayload
    var errorDescription: String? {
        switch self {
        case .disconnected: return "Relay is disconnected"
        case .encoding: return "Message encoding failed"
        case .encryption: return "Message encryption failed"
        case .missingSessionKey: return "This task is still establishing its independent encryption key"
        case .invalidSessionScope: return "The task payload did not match this room and session"
        case .sessionQueueFull: return "The pending task-control queue is full"
        case .sessionPayloadTooLarge: return "The pending task payload is too large"
        case .sessionPayloadExpired: return "The pending task payload expired before delivery"
        case .supersededSessionPayload: return "A newer task-control value replaced this one"
        }
    }
}

import CryptoKit
import Foundation

extension RelayClient {
    // MARK: receive

    func receiveLoop(_ socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            guard let self else { return }
            guard self.task === socket else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async {
                    guard self.task === socket else { return }
                    self.task = nil
                    self.onConnectionChange?(false)
                    self.scheduleReconnect()
                }
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                self.receiveLoop(socket)
            }
        }
    }

    func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let env = try? JSONDecoder().decode(Envelope.self, from: data),
              env.v == 1,
              env.room == pairing.room,
              env.from == peerRole,
              env.to == role.rawValue || env.to == "all",
              env.expiresAt.map({ $0 > Date().timeIntervalSince1970 * 1000 }) ?? true,
              let plain = Crypto.open(nonceB64: env.nonce, boxB64: env.box,
                                      theirPublicKeyB64: pairing.peerPublicKey,
                                      mySecretKeyB64: pairing.mySecretKey),
              let kind = try? JSONDecoder().decode(PayloadKind.self, from: plain)
        else { return }

        let fingerprint = SHA256.hash(data: Data("\(env.nonce).\(env.box)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        if seenCiphertexts.contains(fingerprint) {
            acknowledge(env.deliveryId)
            return
        }

        var accepted = false
        var grantedSessionId: String?
        if kind.type == "session.key.grant",
           let grant = try? JSONDecoder().decode(SessionKeyGrant.self, from: plain) {
            accepted = acceptSessionKeyGrant(grant, room: env.room)
            if accepted { grantedSessionId = grant.sessionId }
        } else if kind.type == "session.sealed",
                  let wrapper = try? JSONDecoder().decode(SessionSealed.self, from: plain),
                  let key = sessionKey(for: wrapper.sessionId),
                  let inner = Crypto.openWithTransferKey(nonceB64: wrapper.nonce,
                                                          boxB64: wrapper.box, key: key),
                  Self.hasExactSessionScope(inner, sessionId: wrapper.sessionId) {
            accepted = handlePlain(inner, scopedSessionId: wrapper.sessionId)
        } else {
            accepted = handlePlain(plain)
        }
        guard accepted else { return }
        rememberCiphertext(fingerprint)
        acknowledge(env.deliveryId)
        if let grantedSessionId {
            // Only the exact room/session grant above may release its backlog.
            flushPendingSessionPayloads(sessionId: grantedSessionId, room: env.room)
        }
    }

    private func handleDeliveryReceipt(_ plain: Data) -> Bool {
        guard let receipt = try? JSONDecoder().decode(DeliveryReceipt.self, from: plain),
              let callback = onDeliveryReceipt else { return false }
        DispatchQueue.main.async { callback(receipt) }
        return true
    }

    /// One arriving payload, decoded and handed to whoever asked for it.
    ///
    /// Every kind below is the same three steps — read it, check it is worth
    /// passing on, deliver it on the main queue — so they are written once. A
    /// payload that does not decode, does not pass its check, or that nobody
    /// is listening for, was not handled.
    private func deliver<T: Decodable>(
        _ type: T.Type, _ plain: Data, to callback: ((T) -> Void)?, when accept: (T) -> Bool = { _ in true }
    ) -> Bool {
        guard let value = try? JSONDecoder().decode(T.self, from: plain), accept(value), let callback else {
            return false
        }
        DispatchQueue.main.async { callback(value) }
        return true
    }

    func handlePlain(_ plain: Data, scopedSessionId: String? = nil) -> Bool {
        guard let kind = try? JSONDecoder().decode(PayloadKind.self, from: plain),
              kind.type != "session.key.grant", kind.type != "session.sealed" else { return false }
        // The computer side of a room hears a phone, not a computer: everything
        // goes to the owner's rules rather than to the handlers below.
        if role == .machine {
            guard let hook = onHubPayload else { return false }
            hook(kind.type, plain)
            return true
        }
        switch kind.type {
        case "approval.request": return deliver(ApprovalRequest.self, plain, to: onRequest)
        // Mac dismisses orphans when Cursor Allow already resolved the gate.
        case "approval.decision": return deliver(ApprovalDecision.self, plain, to: onDecision)
        case "approval.cancel": return deliver(ApprovalCancel.self, plain, to: onApprovalCancel)
        case "approval.resolved": return deliver(ApprovalResolved.self, plain, to: onApprovalResolved)
        case "approvals.status": return deliver(ApprovalsStatus.self, plain, to: onApprovalsStatus)
        case "agent.event": return deliver(AgentEvent.self, plain, to: onAgentEvent)
        case "sessions.status":
            guard let status = Self.decodeSessionsStatus(plain), let callback = onSessions else { return false }
            DispatchQueue.main.async { callback(status) }
            return true
        case "session.activity", "sessions.activity", "session.events":
            return deliver(SessionActivity.self, plain, to: onActivity)
        case "capability.usage.status": return deliver(CapabilityUsageStatus.self, plain, to: onCapabilityUsage)
        case "capability.catalog.status": return deliver(CapabilityCatalogStatus.self, plain, to: onCapabilityCatalog)
        case "session.compact.result": return deliver(SessionCompactResult.self, plain, to: onCompactResult)
        case "session.control.result":
            return deliver(SessionControlResult.self, plain, to: onSessionControlResult) { result in
                ["pause", "resume"].contains(result.action) && result.message.count <= 1_000
            }
        case "tool.update.result":
            return deliver(ToolUpdateResult.self, plain, to: onToolUpdateResult) { result in
                result.message.count <= 1_000 && (result.output ?? "").count <= 4_000
            }
        case "machine.load": return deliver(MachineLoad.self, plain, to: onMachineLoad)
        case "machine.heartbeat": return deliver(MachineHeartbeat.self, plain, to: onMachineHeartbeat)
        case "mesh.event", "mesh.snapshot": return handleMesh(kind.type, plain: plain)
        case "project.policy.status", "project.policy.ack", "project.policy.rejected":
            return handleProjectPolicy(kind.type, plain: plain, scopedSessionId: scopedSessionId)
        case "mesh.claim.release.result":
            // Under the Project's key, and about that Project, or not at all.
            return deliver(MeshClaimReleaseResult.self, plain, to: onClaimReleaseResult) { value in
                value.isWellFormed && value.projectId == scopedSessionId
            }
        case "delivery.receipt": return handleDeliveryReceipt(plain)
        default:
            break
        }
        return false
    }

    private func handleProjectPolicy(
        _ type: String, plain: Data, scopedSessionId: String?
    ) -> Bool {
        guard let scopedSessionId else { return false }
        if type == "project.policy.status", ProjectGovernanceWireValidator.validStatus(plain),
           let value = try? JSONDecoder().decode(ProjectPolicyStatus.self, from: plain),
           value.projectId == scopedSessionId, let callback = onProjectPolicyStatus {
            DispatchQueue.main.async { callback(value) }
            return true
        }
        if type == "project.policy.ack", ProjectGovernanceWireValidator.validAck(plain),
           let value = try? JSONDecoder().decode(ProjectPolicyAck.self, from: plain),
           value.projectId == scopedSessionId, let callback = onProjectPolicyAck {
            DispatchQueue.main.async { callback(value) }
            return true
        }
        if type == "project.policy.rejected", ProjectGovernanceWireValidator.validRejected(plain),
           let value = try? JSONDecoder().decode(ProjectPolicyRejected.self, from: plain),
           value.projectId == scopedSessionId, let callback = onProjectPolicyRejected {
            DispatchQueue.main.async { callback(value) }
            return true
        }
        return false
    }

    private func handleMesh(_ type: String, plain: Data) -> Bool {
        if type == "mesh.event", ProjectMeshWireValidator.validEvent(plain),
           let value = try? JSONDecoder().decode(ProjectMeshEvent.self, from: plain),
           let callback = onMeshEvent {
            DispatchQueue.main.async { callback(value) }
            return true
        }
        if type == "mesh.snapshot", ProjectMeshWireValidator.validSnapshot(plain),
           let value = try? JSONDecoder().decode(ProjectMeshSnapshot.self, from: plain),
           let callback = onMeshSnapshot {
            DispatchQueue.main.async { callback(value) }
            return true
        }
        return false
    }

    /// A session transfer key only authenticates the wrapper's session. Never
    /// accept an unscoped or differently-scoped inner payload under that key.
    static func hasExactSessionScope(_ plain: Data, sessionId: String) -> Bool {
        guard !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let object = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let innerSessionId = object["sessionId"] as? String,
              !innerSessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return innerSessionId == sessionId
    }

    /// Persist the authenticated key before exposing it to either decrypt or
    /// queue-flush paths. A wrong room, empty session, malformed key, or
    /// Keychain failure remains closed and the reliable grant is not acked.
    private func acceptSessionKeyGrant(_ grant: SessionKeyGrant, room: String) -> Bool {
        guard room == pairing.room,
              !room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !grant.sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Crypto.isValidTransferKey(grant.key) else { return false }

        sessionStateLock.lock()
        var updated = sessionKeys
        updated[grant.sessionId] = grant.key
        let saved = SessionKeyVault.save(updated, room: room)
        if saved { sessionKeys = updated }
        sessionStateLock.unlock()
        return saved
    }

    /// SessionsStatus owns lenient per-row decoding, so one malformed session or
    /// activity cannot blank the otherwise valid catalog.
    private static func decodeSessionsStatus(_ plain: Data) -> SessionsStatus? {
        try? JSONDecoder().decode(SessionsStatus.self, from: plain)
    }

    func rememberCiphertext(_ fingerprint: String) {
        guard seenCiphertexts.insert(fingerprint).inserted else { return }
        seenCiphertextOrder.append(fingerprint)
        if seenCiphertextOrder.count > Self.maxSeenCiphertexts {
            let evicted = seenCiphertextOrder.removeFirst()
            seenCiphertexts.remove(evicted)
        }
    }

    func acknowledge(_ deliveryId: String?) {
        guard let deliveryId,
              let ackData = try? JSONSerialization.data(withJSONObject: [
                "type": "relay.ack", "deliveryId": deliveryId,
              ]),
              let ackText = String(data: ackData, encoding: .utf8) else { return }
        task?.send(.string(ackText)) { _ in }
    }
}

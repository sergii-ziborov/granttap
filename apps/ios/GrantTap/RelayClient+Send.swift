import Foundation
import UIKit

enum PendingSessionEnqueueOutcome {
    case queued(needsSubscription: Bool)
    case rejected(Error)
}

extension RelayClient {
    // MARK: send

    func sendHello(recoverPeer: Bool = false) {
        let name = pairing.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        send(payload: Payloads.hello(
            name.isEmpty ? UIDevice.current.name : name,
            role: role, recoverPeer: recoverPeer
        ))
    }

    func sendDecision(requestId: String, decision: String, by: String = "phone",
                      sessionId: String? = nil,
                      completion: ((Error?) -> Void)? = nil) {
        let payload = Payloads.decision(requestId, decision, by: by,
                                        sessionId: sessionId)
        // Approval requests arrive through the device-level E2EE box, so their
        // decisions must use that same always-available channel. A fresh task
        // may not have received its independent session key yet; attempting a
        // session-sealed decision then removed the phone/watch card locally but
        // left the Mac gate waiting until timeout. Transcript and task-control
        // payloads continue to use per-session keys where appropriate.
        send(payload: payload, ttl: 15 * 60,
             deliveryId: "approval-decision-\(requestId)", completion: completion)
    }

    func sendMessage(_ text: String, messageId: String, agent: String? = nil, cwd: String? = nil,
                     sessionId: String?, requestId: String?,
                     attachments: [UserAttachment] = [], attachmentRefs: [UserAttachmentRef] = [],
                     preferredMcp: String? = nil,
                     skill: String? = nil, model: String? = nil,
                     permissionMode: String? = nil,
                     effort: String? = nil,
                     completion: ((Error?) -> Void)? = nil) {
        let payload = Payloads.message(text, messageId: messageId, agent: agent, cwd: cwd,
                                       sessionId: sessionId, requestId: requestId,
                                       attachments: attachments, attachmentRefs: attachmentRefs,
                                       preferredMcp: preferredMcp,
                                       skill: skill, model: model,
                                       permissionMode: permissionMode, effort: effort)
        // Always device-box user.message. Session-sealed chat broke delivery when
        // the Mac monitor lacked the task key (no unwrap → no delivery.receipt →
        // forever Queued). The outer envelope is already E2EE to this machine;
        // session keys remain for activity/compact grants.
        send(payload: payload, ttl: DeliveryOutboxPolicy.userMessageRelayTTLSeconds,
             deliveryId: messageId, completion: completion)
    }

    /// An attachment ahead of its message: the bytes go now, the message
    /// that follows names them.
    func sendAttachmentUpload(_ upload: UserAttachmentUpload, completion: ((Error?) -> Void)? = nil) {
        send(payload: upload, ttl: DeliveryOutboxPolicy.userMessageRelayTTLSeconds,
             deliveryId: "attachment-\(upload.attachmentId)", completion: completion)
    }

    func sendSubscription(sessionId: String, active: Bool) {
        send(payload: SessionSubscription(type: "session.subscribe", sessionId: sessionId,
                                          active: active,
                                          createdAt: Date().timeIntervalSince1970 * 1000), ttl: 60)
    }

    func requestSessionEvents(sessionId: String, threadId: String? = nil) {
        send(payload: SessionEventsRequest(type: "session.events", sessionId: sessionId, threadId: threadId,
                                           createdAt: Date().timeIntervalSince1970 * 1000), ttl: 60)
    }

    /// Ask the Mac monitor to rescan Codex/Claude chats and push sessions.status now.
    func requestSessionsRefresh() {
        send(payload: SessionsRefresh(type: "sessions.refresh",
                                      createdAt: Date().timeIntervalSince1970 * 1000),
             ttl: 60)
    }

    func sendSessionAccess(sessionId: String, accessLevel: String) {
        sendSession(payload: SessionAccessSet(type: "session.access.set", sessionId: sessionId,
                                              accessLevel: accessLevel,
                                              createdAt: Date().timeIntervalSince1970 * 1000),
                    sessionId: sessionId)
    }

    func sendSessionMcp(sessionId: String, serverName: String, allowed: Bool) {
        sendSession(payload: SessionMcpSet(type: "session.mcp.set", scope: "task", sessionId: sessionId,
                                           serverName: serverName, allowed: allowed,
                                           createdAt: Date().timeIntervalSince1970 * 1000),
                    sessionId: sessionId)
    }

    func sendSessionSkill(sessionId: String, skillName: String, allowed: Bool) {
        sendSession(payload: SessionSkillSet(type: "session.skill.set", scope: "task", sessionId: sessionId,
                                             skillName: skillName, allowed: allowed,
                                             createdAt: Date().timeIntervalSince1970 * 1000),
                    sessionId: sessionId)
    }

    func sendSessionShell(sessionId: String, allowed: Bool) {
        sendSession(payload: SessionShellSet(type: "session.shell.set", scope: "task", sessionId: sessionId,
                                             allowed: allowed,
                                             createdAt: Date().timeIntervalSince1970 * 1000),
                    sessionId: sessionId)
    }

    func sendGlobalMcp(serverName: String, allowed: Bool) {
        send(payload: SessionMcpSet(type: "session.mcp.set", scope: "global", sessionId: nil,
                                    serverName: serverName, allowed: allowed,
                                    createdAt: Date().timeIntervalSince1970 * 1000))
    }

    func sendGlobalSkill(skillName: String, allowed: Bool) {
        send(payload: SessionSkillSet(type: "session.skill.set", scope: "global", sessionId: nil,
                                      skillName: skillName, allowed: allowed,
                                      createdAt: Date().timeIntervalSince1970 * 1000))
    }

    func sendGlobalShell(allowed: Bool) {
        send(payload: SessionShellSet(type: "session.shell.set", scope: "global", sessionId: nil,
                                      allowed: allowed,
                                      createdAt: Date().timeIntervalSince1970 * 1000))
    }

    func updateTool(_ payload: ToolUpdate) {
        send(payload: payload, ttl: 5 * 60)
    }

    func compactSession(_ sessionId: String) {
        sendSession(payload: SessionCompact(type: "session.compact", sessionId: sessionId,
                                            createdAt: Date().timeIntervalSince1970 * 1000),
                    sessionId: sessionId, ttl: 5 * 60)
    }

    /// Hold or release one chat on its computer.
    func controlSession(_ sessionId: String, action: String, continue shouldContinue: Bool = false) {
        sendSession(payload: SessionControl(type: "session.control", sessionId: sessionId, action: action,
                                            continue: shouldContinue ? true : nil,
                                            createdAt: Date().timeIntervalSince1970 * 1000),
                    sessionId: sessionId, ttl: 5 * 60)
    }

    func sendConfig(
        enabled: Bool? = nil,
        excludeSession: String? = nil,
        includeSession: String? = nil,
        autoAcceptDefault: String? = nil,
        autoAcceptSessionId: String? = nil,
        autoAcceptSessionLevel: String? = nil,
        clearAutoAcceptSession: Bool = false,
        autoAcceptPaused: Bool? = nil
    ) {
        var sessionSet: AutoAcceptSessionSet? = nil
        if let sid = autoAcceptSessionId {
            sessionSet = AutoAcceptSessionSet(
                sessionId: sid,
                level: clearAutoAcceptSession ? nil : autoAcceptSessionLevel
            )
        }
        send(payload: ConfigSet(
            type: "config.set",
            enabled: enabled,
            excludeSession: excludeSession,
            includeSession: includeSession,
            autoAcceptDefault: autoAcceptDefault,
            autoAcceptSession: sessionSet,
            autoAcceptPaused: autoAcceptPaused,
            provider: nil,
            providerEnabled: nil,
            meshEnabled: nil,
            createdAt: Date().timeIntervalSince1970 * 1000
        ))
    }

    func sendAgentMeshConfig(
        provider: String? = nil,
        providerEnabled: Bool? = nil,
        meshEnabled: Bool? = nil
    ) {
        send(payload: ConfigSet(
            type: "config.set", enabled: nil, excludeSession: nil, includeSession: nil,
            autoAcceptDefault: nil, autoAcceptSession: nil, autoAcceptPaused: nil,
            provider: provider, providerEnabled: providerEnabled, meshEnabled: meshEnabled,
            createdAt: Date().timeIntervalSince1970 * 1_000
        ))
    }

    func send<T: Codable>(payload: T, to addressee: String? = nil, ttl: TimeInterval? = 15 * 60,
                          deliveryId: String? = nil,
                          completion: ((Error?) -> Void)? = nil) {
        // Strip null optionals — Swift JSONEncoder emits `null`, and older Mac
        // Zod schemas reject those (every phone message looked like "ничего").
        guard let body = try? Self.encodeOmittingNulls(payload) else {
            completion?(RelaySendError.encoding)
            return
        }
        sendRaw(body, to: addressee, ttl: ttl, deliveryId: deliveryId, completion: completion)
    }

    /// Bytes already in wire shape — a member's payload passed on as it came —
    /// sealed and sent like any other.
    func sendRaw(_ body: Data, to addressee: String? = nil, ttl: TimeInterval? = 15 * 60,
                 deliveryId: String? = nil,
                 completion: ((Error?) -> Void)? = nil) {
        let to = addressee ?? peerRole.rawValue
        var peers = [pairing.peerPublicKey]
        if role == .phone, to == peerRole.rawValue || to == "all",
           let extras = pairing.extraPeerPublicKeys {
            for key in extras where !peers.contains(key) { peers.append(key) }
        }
        guard let task else {
            completion?(RelaySendError.disconnected)
            return
        }
        var remaining = peers.count
        var firstError: Error?
        for peer in peers {
            guard let sealed = try? Crypto.seal(body,
                                                theirPublicKeyB64: peer,
                                                mySecretKeyB64: pairing.mySecretKey) else {
                completion?(RelaySendError.encryption)
                return
            }
            let env = Envelope(room: pairing.room, from: role, to: to,
                               senderId: pairing.senderId,
                               deliveryId: deliveryId ?? UUID().uuidString.lowercased(),
                               wake: nil,
                               expiresAt: ttl.map {
                                   ((Date().timeIntervalSince1970 + $0) * 1000).rounded(.down)
                               },
                               nonce: sealed.nonce, box: sealed.box)
            guard let data = try? Self.encodeOmittingNulls(env),
                  let text = String(data: data, encoding: .utf8) else {
                completion?(RelaySendError.encoding)
                return
            }
            task.send(.string(text)) { error in
                if firstError == nil { firstError = error }
                remaining -= 1
                if remaining == 0 { completion?(firstError) }
            }
        }
    }


}

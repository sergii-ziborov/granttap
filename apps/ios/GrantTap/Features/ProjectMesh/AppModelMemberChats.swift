import Foundation

/// The Project's chats, shared with a member.
///
/// A member's phone sees this phone as a computer. What that computer says
/// about its chats is what this phone forwards from the real ones: the
/// session list of every computer in the Project, cut down to the Project's
/// own chats, and each transcript and reply for them as it arrives, sealed
/// under the same per-chat key the computer gave this phone. What the member
/// writes into a chat travels the other way, to the computer that owns it,
/// and the computer's receipt comes back to the member. Approvals never
/// leave this phone: a member can watch a chat and write to it, not decide
/// for it.
struct MemberSessionsStatus: Codable {
    var type = "sessions.status"
    let machine: String
    let sessions: [SessionInfo]
    let history: [SessionInfo]
    let activities: [SessionActivity]
    var tokensRecent = 0
    var tokenWindowHours = 24
    let generatedAt: Double
}

@MainActor
extension AppModel {
    static let memberTranscriptEntries = 40
    static let memberTranscripts = 24

    /// Members of a Project who may watch its chats and are here now.
    func chatWatchers(for projectId: String) -> [MemberLink] {
        memberLinks(for: projectId).filter { $0.rules.canSeeChats && memberLinkConnected.contains($0.id) }
    }

    /// A room paired with another person's phone, not a computer of this
    /// phone's own. What arrives from one is theirs to share, not this phone's.
    func isHubRoom(_ room: String) -> Bool {
        connectionRegistry.connections.first { $0.id == room }?.pairing.isHub == true
    }

    /// The computers of this phone's own that take part in a Project.
    func ownComputerRooms(for projectId: String) -> Set<String> {
        computerRooms(for: projectId).filter { !isHubRoom($0) }
    }

    /// The Project a chat belongs to, as its computer reported it.
    func projectId(ofSession sessionId: String) -> String? {
        let known = sessions.first { $0.sessionId == sessionId } ?? sessionHistory.first { $0.sessionId == sessionId }
        return known?.projectId
    }

    /// A chat of this Project on one of this phone's own computers.
    func isProjectChat(_ sessionId: String, projectId: String) -> Bool {
        guard self.projectId(ofSession: sessionId) == projectId,
              let room = sourceRoom(forSessionId: sessionId) else { return false }
        return ownComputerRooms(for: projectId).contains(room)
    }

    /// The Project's chats as they stand, in the shape a computer reports
    /// them: the live ones, the recent ones, and a bounded transcript each.
    func memberSessionsStatus(projectId: String, includeTranscripts: Bool = true,
                              now: Double = Date().timeIntervalSince1970 * 1_000) -> MemberSessionsStatus {
        let live = sessions.filter { isProjectChat($0.sessionId, projectId: projectId) }
        let history = sessionHistory.filter { isProjectChat($0.sessionId, projectId: projectId) }
        var transcripts: [SessionActivity] = []
        if includeTranscripts {
            let ids = (live + history).map(\.sessionId)
            transcripts = ids.prefix(Self.memberTranscripts).compactMap { id in
                activities[id].map { Self.boundedTranscript($0) }
            }
        }
        return MemberSessionsStatus(
            machine: hubDisplayName, sessions: live, history: history,
            activities: transcripts, generatedAt: now
        )
    }

    /// The end of a transcript, as many rows as a first look needs.
    static func boundedTranscript(_ activity: SessionActivity) -> SessionActivity {
        SessionActivity(
            type: activity.type, sessionId: activity.sessionId, agent: activity.agent, state: activity.state,
            threadId: activity.threadId, entries: Array(activity.entries.suffix(memberTranscriptEntries)),
            generatedAt: activity.generatedAt
        )
    }

    /// Everything a member needs to see the Project's chats as they stand.
    func forwardChatsToMember(_ link: MemberLink) {
        guard link.rules.canSeeChats, memberLinkConnected.contains(link.id),
              let client = meshEndpointRelaysById[link.id] else { return }
        let status = memberSessionsStatus(projectId: link.projectId)
        guard !status.sessions.isEmpty || !status.history.isEmpty else { return }
        client.send(payload: status, ttl: 15 * 60)
    }

    /// A computer's fresh session list: the Project's part of it, to each watcher.
    func forwardStatusToMembers(fromRoom room: String) {
        guard !isHubRoom(room) else { return }
        for projectId in Set(chatWatchers().map(\.projectId)) where ownComputerRooms(for: projectId).contains(room) {
            let status = memberSessionsStatus(projectId: projectId, includeTranscripts: false)
            for link in chatWatchers(for: projectId) {
                meshEndpointRelaysById[link.id]?.send(payload: status, ttl: 15 * 60)
            }
        }
    }

    private func chatWatchers() -> [MemberLink] {
        memberLinks.filter { $0.rules.canSeeChats && memberLinkConnected.contains($0.id) }
    }

    /// A transcript as it changed, to each watcher of its Project.
    func forwardActivityToMembers(_ activity: SessionActivity, fromRoom room: String) {
        forwardChatPayload(activity, sessionId: activity.sessionId, fromRoom: room)
    }

    /// A reply or a status for one chat, to each watcher of its Project.
    func forwardAgentEventToMembers(_ event: AgentEvent, fromRoom room: String?) {
        guard let room,
              let sessionId = event.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionId.isEmpty else { return }
        forwardChatPayload(event, sessionId: sessionId, fromRoom: room)
    }

    /// One chat's payload to its Project's watchers: under the chat's own key
    /// when this phone holds it, in the pairwise box when it does not.
    @discardableResult
    func forwardChatPayload<T: Codable>(_ payload: T, sessionId: String, fromRoom room: String) -> Int {
        guard !isHubRoom(room), let projectId = projectId(ofSession: sessionId),
              ownComputerRooms(for: projectId).contains(room) else { return 0 }
        let watchers = chatWatchers(for: projectId)
        guard !watchers.isEmpty else { return 0 }
        let sealed = meshRelay(forRoom: room)?.sessionKey(for: sessionId) != nil
        for link in watchers {
            if sealed {
                forwardMesh(payload, scopeId: sessionId, purpose: "session", sourceRoom: room, targetRoom: link.id)
            } else {
                meshEndpointRelaysById[link.id]?.send(payload: payload, ttl: 15 * 60)
            }
        }
        return watchers.count
    }

    // MARK: What a member writes

    /// A member's words into one of the Project's chats, on to the computer
    /// that owns it. A chat outside the Project, or on no computer of this
    /// phone's own, is refused with a receipt so the member's outbox settles.
    @discardableResult
    func forwardMemberMessage(_ data: Data, link: MemberLink) -> Bool {
        guard let message = try? JSONDecoder().decode(UserMessage.self, from: data),
              let messageId = message.messageId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !messageId.isEmpty else { return false }
        guard let sessionId = message.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionId.isEmpty,
              isProjectChat(sessionId, projectId: link.projectId),
              let room = sourceRoom(forSessionId: sessionId),
              let relay = relaysByRoom[room] else {
            refuseMemberMessage(messageId, link: link, detail: L("That chat is not one of this Project's."))
            return false
        }
        memberForwardedMessages[messageId] = link.id
        relay.send(payload: Self.memberMessage(message, sessionId: sessionId, messageId: messageId),
                   ttl: DeliveryOutboxPolicy.userMessageRelayTTLSeconds, deliveryId: messageId)
        append("member \(link.name) wrote to \(sessionId.prefix(8))")
        return true
    }

    /// A member writes into a chat that already exists, and writes only what
    /// is said in it: the text, and what was attached to it.
    ///
    /// How a turn is run belongs to the chat and to this phone — the model,
    /// the effort, the provider's permission mode, the agent, the working
    /// directory. A member's message that named them would have changed the
    /// terms the work runs under from another phone, silently and for every
    /// turn after it, so those fields are not carried over.
    static func memberMessage(_ message: UserMessage, sessionId: String, messageId: String) -> UserMessage {
        UserMessage(
            type: "user.message", messageId: messageId, text: message.text,
            requestId: message.requestId, sessionId: sessionId,
            attachments: message.attachments, attachmentRefs: message.attachmentRefs,
            createdAt: message.createdAt
        )
    }

    func refuseMemberMessage(_ messageId: String, link: MemberLink, detail: String) {
        let receipt = DeliveryReceipt(
            type: "delivery.receipt", messageId: messageId, status: "rejected", error: detail,
            receivedAt: Date().timeIntervalSince1970 * 1_000
        )
        meshEndpointRelaysById[link.id]?.send(payload: receipt, ttl: 15 * 60)
    }

    /// The computer's answer to a member's message goes to that member, not
    /// into this phone's outbox, which never held it.
    @discardableResult
    func handOffReceiptToMember(_ receipt: DeliveryReceipt) -> Bool {
        let messageId = receipt.messageId.lowercased()
        guard let key = memberForwardedMessages.keys.first(where: { $0.lowercased() == messageId }),
              let linkId = memberForwardedMessages[key] else { return false }
        if receipt.status == "accepted" || receipt.status == "rejected" {
            memberForwardedMessages.removeValue(forKey: key)
        }
        meshEndpointRelaysById[linkId]?.send(payload: receipt, ttl: 24 * 60 * 60)
        return true
    }

    /// A pause, a resume, a transcript request, or a subscription for one of
    /// the Project's chats, on to the computer that owns it.
    @discardableResult
    func forwardMemberChatControl(type: String, data: Data, link: MemberLink) -> Bool {
        let sessionId: String?
        switch type {
        case "session.control":
            sessionId = (try? JSONDecoder().decode(SessionControl.self, from: data))?.sessionId
        case "session.subscribe":
            sessionId = (try? JSONDecoder().decode(SessionSubscription.self, from: data))?.sessionId
        case "session.events":
            sessionId = (try? JSONDecoder().decode(SessionEventsRequest.self, from: data))?.sessionId
        default:
            sessionId = nil
        }
        guard let sessionId, isProjectChat(sessionId, projectId: link.projectId),
              let room = sourceRoom(forSessionId: sessionId),
              let relay = relaysByRoom[room] else { return false }
        if type == "session.control" { memberForwardedControls[sessionId] = link.id }
        relay.sendRaw(data, ttl: type == "session.control" ? 5 * 60 : 60)
        return true
    }

    /// The computer's word on a pause a member asked for goes to that member,
    /// so their screen learns what happened rather than keeping its own guess.
    @discardableResult
    func handOffControlResultToMember(_ result: SessionControlResult) -> Bool {
        guard let linkId = memberForwardedControls.removeValue(forKey: result.sessionId),
              let client = meshEndpointRelaysById[linkId] else { return false }
        client.send(payload: result, ttl: 15 * 60)
        return true
    }
}

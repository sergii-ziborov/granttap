import Foundation

/// What arrives from a member's phone, and what is sent back to it.
///
/// A member speaks to this phone the way a phone speaks to a computer, so what
/// arrives is the same set of payloads. Each is let through by one rule of the
/// member's role, and what no rule names is refused here, with the rule named,
/// rather than reaching a computer.
@MainActor
extension AppModel {
    func forwardGovernanceStatusToMembers(_ status: ProjectPolicyStatus, fromRoom room: String) {
        for link in memberLinks(for: status.projectId) where link.id != room {
            forwardMesh(status, scopeId: status.projectId, purpose: "project", sourceRoom: room, targetRoom: link.id)
        }
    }

    /// The key an edit is remembered under: its own name when it has one, so
    /// two members editing the same revision at once each get their answer;
    /// the project and revision otherwise.
    static func policyEditKey(projectId: String, revision: Int, requestId: String?) -> String {
        if let requestId = requestId?.trimmingCharacters(in: .whitespacesAndNewlines), !requestId.isEmpty {
            return "req:\(requestId)"
        }
        return "\(projectId):\(revision)"
    }

    /// A computer's answer to an edit a member made goes to that member, not
    /// onto this phone's own Governance screen.
    func handOffRejectionToMember(_ rejected: ProjectPolicyRejected) -> Bool {
        let key = Self.policyEditKey(
            projectId: rejected.projectId, revision: rejected.expectedRevision + 1, requestId: rejected.requestId
        )
        guard let linkId = memberForwardedSets.removeValue(forKey: key),
              let client = meshEndpointRelaysById[linkId] else { return false }
        client.sendSession(payload: rejected, sessionId: rejected.projectId, ttl: 15 * 60)
        return true
    }

    // MARK: What a member sends

    /// Every payload a member's phone sends, let through by the member's rules
    /// and kept inside the member's Project. The sender is the room the
    /// payload came through, never anything the payload says about itself.
    func handleMemberPayload(type: String, data: Data, linkId: String) {
        guard let index = memberLinks.firstIndex(where: { $0.id == linkId }) else { return }
        memberLinks[index].lastSeenAt = Date().timeIntervalSince1970 * 1_000
        let link = memberLinks[index]
        guard MemberHubPolicy.allows(type, rules: link.rules) else {
            refuseMemberPayload(type: type, data: data, link: link)
            append("member \(link.name) refused: \(type)")
            return
        }
        switch type {
        case "project.policy.set":
            guard ProjectGovernanceWireValidator.validSet(data),
                  let set = try? JSONDecoder().decode(ProjectPolicySet.self, from: data),
                  set.projectId == link.projectId else { return }
            let rooms = ownComputerRooms(for: set.projectId)
            guard !rooms.isEmpty else {
                refuseMemberPolicy(set, link: link, detail: L("No computer in this Project is reachable right now."))
                return
            }
            memberForwardedSets[Self.policyEditKey(
                projectId: set.projectId, revision: set.policy.revision, requestId: set.requestId
            )] = link.id
            for room in rooms.sorted() {
                relaysByRoom[room]?.sendSession(
                    payload: set, sessionId: set.projectId, ttl: 24 * 60 * 60,
                    deliveryId: "member-policy-\(set.projectId)-\(set.policy.revision)-\(link.id.prefix(8))"
                )
            }
        case "mesh.event":
            acceptMemberEvent(data, link: link)
        case "mesh.snapshot":
            acceptMemberSnapshot(data, link: link)
        case "mesh.handoff.prepare":
            forwardMemberHandoff(data, link: link)
        case "mesh.claim.release":
            forwardMemberClaimRelease(data, link: link)
        case "user.message":
            forwardMemberMessage(data, link: link)
        case "session.control", "session.subscribe", "session.events":
            forwardMemberChatControl(type: type, data: data, link: link)
        case "sessions.refresh":
            for room in ownComputerRooms(for: link.projectId).sorted() {
                relaysByRoom[room]?.requestSessionsRefresh()
            }
        default:
            break
        }
    }

    /// A refusal the member's phone can show: an edit is answered like a
    /// computer answers one, a message with the receipt its outbox waits for.
    private func refuseMemberPayload(type: String, data: Data, link: MemberLink) {
        switch type {
        case "project.policy.set":
            if let set = try? JSONDecoder().decode(ProjectPolicySet.self, from: data) {
                refuseMemberPolicy(set, link: link, detail: MemberHubPolicy.refusal(type))
            }
        case "user.message":
            if let messageId = (try? JSONDecoder().decode(UserMessage.self, from: data))?.messageId, !messageId.isEmpty {
                refuseMemberMessage(messageId, link: link, detail: MemberHubPolicy.refusal(type))
            }
        case "mesh.claim.release":
            if let request = try? JSONDecoder().decode(MeshClaimRelease.self, from: data), request.isWellFormed {
                refuseMemberRelease(request, link: link, reason: "not_allowed", detail: MemberHubPolicy.refusal(type))
            }
        default:
            break
        }
    }

    private func refuseMemberPolicy(_ set: ProjectPolicySet, link: MemberLink, detail: String) {
        let rejected = ProjectPolicyRejected(
            type: "project.policy.rejected", sessionId: set.projectId, projectId: set.projectId,
            expectedRevision: set.expectedRevision,
            currentRevision: projectGovernance[set.projectId]?.revision,
            reason: "unknown", detail: detail, requestId: set.requestId,
            generatedAt: Date().timeIntervalSince1970 * 1_000
        )
        meshEndpointRelaysById[link.id]?.sendSession(payload: rejected, sessionId: set.projectId, ttl: 15 * 60)
    }

    // MARK: Encoding helpers
}

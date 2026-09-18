import Foundation
import TweetNacl
import UIKit

enum MemberInviteError: LocalizedError {
    case noComputer, noProject, keyGeneration, relayUnavailable, storage

    var errorDescription: String? {
        switch self {
        case .noComputer: return L("Connect a computer before inviting a person.")
        case .noProject: return L("This Project has not been reported yet.")
        case .keyGeneration: return L("GrantTap could not create the invite keys.")
        case .relayUnavailable: return L("The relay could not hold the one-time invite.")
        case .storage: return L("The invite could not be stored securely.")
        }
    }
}

/// A heartbeat in the shape a computer sends, so a member's phone shows this
/// phone as live while it forwards the Project.
struct HubHeartbeat: Codable {
    var type = "machine.heartbeat"
    let machine: String
    let createdAt: Double
}

@MainActor
extension AppModel {
    typealias MemberInviteParker = (URLRequest, Data) async throws -> Int

    static let memberInviteLifetimeMs: Double = 15 * 60 * 1_000
    static let memberHeartbeatSeconds: TimeInterval = 30

    var hubDisplayName: String { UIDevice.current.name }

    func memberLinks(for projectId: String) -> [MemberLink] {
        memberLinks.filter { $0.projectId == projectId }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Rooms of computers that take part in a Project — the ones a policy or
    /// a hand-off is for. A member's phone and a bot endpoint hear the Project
    /// but are not asked to apply anything.
    func computerRooms(for projectId: String) -> Set<String> {
        (meshProjectSourceRooms[projectId] ?? []).filter { meshEndpointRoomToId[$0] == nil }
    }

    // MARK: Invite

    /// Mint a pairing for another phone and park its half with the relay.
    ///
    /// The other phone scans the code the way it would scan a computer's; to
    /// it, this phone is a computer named after its owner and the Project.
    /// This phone keeps the other half and speaks as the computer would.
    func createMemberInvite(
        projectId: String, name: String, role: MemberRole, rules: MemberRules,
        parker: MemberInviteParker? = nil
    ) async throws -> String {
        guard let sourcePairing = connectionRegistry.preferred?.pairing else {
            throw MemberInviteError.noComputer
        }
        guard let snapshot = meshSnapshots[projectId] else { throw MemberInviteError.noProject }
        let hub: (publicKey: Data, secretKey: Data)
        let member: (publicKey: Data, secretKey: Data)
        do {
            hub = try NaclBox.keyPair()
            member = try NaclBox.keyPair()
        } catch {
            throw MemberInviteError.keyGeneration
        }
        let now = Date().timeIntervalSince1970 * 1_000
        let room = Self.hex(Crypto.randomBytes(16))
        let pushAuth = Self.hex(Crypto.randomBytes(32))
        let senderId = Self.hex(Crypto.randomBytes(4))
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceName = "\(hubDisplayName) · \(snapshot.project.name)"
        let memberPairing = Pairing(
            relayUrl: sourcePairing.relayUrl, room: room, role: "phone",
            deviceName: deviceName, senderId: senderId,
            myPublicKey: member.publicKey.base64EncodedString(),
            mySecretKey: member.secretKey.base64EncodedString(),
            peerPublicKey: hub.publicKey.base64EncodedString(), pushAuth: pushAuth,
            hub: true
        )
        let hubPairing = Pairing(
            relayUrl: sourcePairing.relayUrl, room: room, role: "machine",
            deviceName: deviceName, senderId: "hub-\(senderId)",
            myPublicKey: hub.publicKey.base64EncodedString(),
            mySecretKey: hub.secretKey.base64EncodedString(),
            peerPublicKey: member.publicKey.base64EncodedString(), pushAuth: pushAuth
        )
        let data = try JSONEncoder().encode(memberPairing)
        let transferKey = Self.base64URL(Crypto.randomBytes(32))
        guard let sealed = Crypto.openableSeal(data, key: transferKey),
              let base = Pairing.normalizedPairingHTTPBase(sourcePairing.relayUrl),
              let url = URL(string: "\(base)/pair/\(Self.hex(Crypto.randomBytes(16)))")
        else { throw MemberInviteError.keyGeneration }
        let body = try JSONEncoder().encode(sealed)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let status: Int
        if let parker {
            status = try await parker(request, body)
        } else {
            let (_, response) = try await URLSession.shared.upload(for: request, from: body)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        }
        guard status == 201 else { throw MemberInviteError.relayUnavailable }
        let link = MemberLink(
            id: room, projectId: projectId, name: cleanName.isEmpty ? L("Member") : cleanName,
            role: role, rules: rules, createdAt: now,
            inviteExpiresAt: now + Self.memberInviteLifetimeMs, hubPairing: hubPairing
        )
        memberLinks.append(link)
        guard MemberLinkStore.save(memberLinks) else {
            memberLinks.removeAll { $0.id == room }
            throw MemberInviteError.storage
        }
        attachMemberLink(link)
        let mailbox = url.lastPathComponent
        return Self.memberInviteURI(base: base, mailbox: mailbox, key: transferKey)
    }

    /// The same link a computer prints: the other phone's pairing sheet
    /// already reads it.
    static func memberInviteURI(base: String, mailbox: String, key: String) -> String {
        var components = URLComponents()
        components.scheme = "granttap"
        components.host = "pair-v2"
        components.queryItems = [
            .init(name: "v", value: "2"), .init(name: "u", value: base),
            .init(name: "m", value: mailbox), .init(name: "k", value: key),
        ]
        return components.string ?? ""
    }

    // MARK: Links

    func updateMemberLink(_ link: MemberLink) {
        guard let index = memberLinks.firstIndex(where: { $0.id == link.id }) else { return }
        let before = memberLinks[index]
        memberLinks[index] = link
        guard MemberLinkStore.save(memberLinks) else {
            memberLinks[index] = before
            append(L("Member permissions could not be stored securely — the previous rights stay."))
            return
        }
        // Chats newly allowed are handed over at once, not on the next hello.
        if link.rules.canSeeChats, !before.rules.canSeeChats { forwardChatsToMember(link) }
    }

    func removeMemberLink(id: String) {
        guard memberLinks.contains(where: { $0.id == id }) else { return }
        let previous = memberLinks
        let next = memberLinks.filter { $0.id != id }
        guard MemberLinkStore.save(next) else {
            append(L("The member could not be removed securely — they are still in the Project."))
            return
        }
        memberLinks = next
        memberHubTimers[id]?.invalidate()
        memberHubTimers.removeValue(forKey: id)
        memberLinkConnected.remove(id)
        meshEndpointRelaysById[id]?.disconnect()
        meshEndpointRelaysById.removeValue(forKey: id)
        meshEndpointRoomToId.removeValue(forKey: id)
        for projectId in meshProjectSourceRooms.keys { meshProjectSourceRooms[projectId]?.remove(id) }
        // What this member spoke for is nobody's now: invited again, they
        // arrive through a new pairing and must be able to speak for it again.
        meshContributionRooms = meshContributionRooms.filter { $0.value != id }
    }

    func attachStoredMemberLinks() {
        for link in memberLinks { attachMemberLink(link) }
    }

    func attachMemberLink(_ link: MemberLink) {
        guard agentMeshPreferences.meshEnabled else { return }
        meshEndpointRelaysById[link.id]?.disconnect()
        let client = RelayClient(pairing: link.hubPairing)
        meshEndpointRoomToId[link.id] = link.id
        meshEndpointRelaysById[link.id] = client
        meshProjectSourceRooms[link.projectId, default: []].insert(link.id)
        let linkId = link.id
        client.onConnectionChange = { [weak self] up in
            Task { @MainActor [weak self] in self?.memberLinkConnection(up: up, linkId: linkId) }
        }
        client.onHubPayload = { [weak self] type, data in
            Task { @MainActor [weak self] in self?.handleMemberPayload(type: type, data: data, linkId: linkId) }
        }
        client.connect()
    }

    func isMemberLinkConnected(_ id: String) -> Bool { memberLinkConnected.contains(id) }

    func memberLinkConnection(up: Bool, linkId: String) {
        guard let index = memberLinks.firstIndex(where: { $0.id == linkId }) else { return }
        let now = Date().timeIntervalSince1970 * 1_000
        if up {
            memberLinkConnected.insert(linkId)
            if memberLinks[index].joinedAt == nil { memberLinks[index].joinedAt = now }
            memberLinks[index].lastSeenAt = now
            MemberLinkStore.save(memberLinks)
            sendHubHeartbeat(linkId: linkId)
            memberHubTimers[linkId]?.invalidate()
            memberHubTimers[linkId] = Timer.scheduledTimer(
                withTimeInterval: Self.memberHeartbeatSeconds, repeats: true
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.sendHubHeartbeat(linkId: linkId) }
            }
            forwardProjectToMember(memberLinks[index])
        } else {
            memberLinkConnected.remove(linkId)
            memberLinks[index].lastSeenAt = now
            MemberLinkStore.save(memberLinks)
            memberHubTimers[linkId]?.invalidate()
            memberHubTimers.removeValue(forKey: linkId)
        }
    }

    func sendHubHeartbeat(linkId: String) {
        guard memberLinkConnected.contains(linkId), let client = meshEndpointRelaysById[linkId] else { return }
        client.send(payload: HubHeartbeat(machine: hubDisplayName, createdAt: Date().timeIntervalSince1970 * 1_000), ttl: 60)
    }

    /// What the member's phone needs first: the Project as it stands and its
    /// Governance, from a computer that holds the Project's key, and the
    /// Project's chats when the member may see them.
    func forwardProjectToMember(_ link: MemberLink) {
        guard let source = computerRooms(for: link.projectId).sorted().first else { return }
        if let snapshot = meshSnapshots[link.projectId] {
            forwardMesh(snapshot, scopeId: link.projectId, purpose: "project", sourceRoom: source, targetRoom: link.id)
        }
        if let status = projectGovernance[link.projectId]?.wireStatus() {
            forwardMesh(status, scopeId: link.projectId, purpose: "project", sourceRoom: source, targetRoom: link.id)
        }
        forwardChatsToMember(link)
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension ProjectGovernanceProjection {
    /// The projection as the status a computer would send, so a member's phone
    /// can be handed what this phone already knows.
    func wireStatus(now: Double = Date().timeIntervalSince1970 * 1_000) -> ProjectPolicyStatus? {
        guard let policy else { return nil }
        let grouped = Dictionary(grouping: coverage) { "\($0.endpointId)\u{1f}\($0.provider)" }
        let endpoints: [ProjectPolicyAcknowledgement] = grouped.values.compactMap { rows in
            guard let first = rows.first else { return nil }
            return ProjectPolicyAcknowledgement(
                projectId: projectId, policyRevision: policy.revision,
                endpointId: first.endpointId, provider: first.provider,
                capabilities: rows.compactMap { row in
                    ProjectCapabilityKind(rawValue: row.capability).map {
                        ProjectCapabilityCoverage(kind: $0, status: row.status)
                    }
                },
                observedAt: updatedAt
            )
        }.sorted { $0.id < $1.id }
        return ProjectPolicyStatus(
            type: "project.policy.status", sessionId: projectId, projectId: projectId,
            policy: policy,
            coverage: ProjectPolicyCoverage(
                projectId: projectId, policyRevision: policy.revision, enforcement: policy.enforcement,
                requiredCapabilities: requiredCapabilities ?? [], endpoints: endpoints,
                strictReady: strictReady ?? true
            ),
            generatedAt: now
        )
    }
}

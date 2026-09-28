import Foundation
import TweetNacl
import UIKit

enum MemberInviteError: LocalizedError {
    case noComputer, noProject, keyGeneration, relayUnavailable, storage, invalidLifetime, invalidScope, invalidAccount, linkLimit

    var errorDescription: String? {
        switch self {
        case .noComputer: return L("Connect a computer before inviting a person.")
        case .noProject: return L("This Mesh has not been reported yet.")
        case .keyGeneration: return L("GrantTap could not create the invite keys.")
        case .relayUnavailable: return L("The relay could not hold the one-time invite.")
        case .storage: return L("The invite could not be stored securely.")
        case .invalidLifetime: return L("Choose a supported invite lifetime.")
        case .invalidScope: return L("This device cannot share one of the selected Mesh spaces from its connected computer.")
        case .invalidAccount: return L("The company account needs access to every repository in the selected Mesh spaces.")
        case .linkLimit: return L("Remove an unused member invite before creating another one.")
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

    static let memberInviteLifetimeMinutes = [5, 15]
    static let memberHeartbeatSeconds: TimeInterval = 30

    var hubDisplayName: String { UIDevice.current.name }

    func memberLinks(for projectId: String) -> [MemberLink] {
        memberLinks.filter { memberCanAccessProject($0, projectId: projectId) }
            .sorted { $0.createdAt < $1.createdAt }
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
        lifetimeMinutes: Int = 15,
        projectIds: Set<String>? = nil,
        accountId: String,
        parker: MemberInviteParker? = nil
    ) async throws -> String {
        guard Self.memberInviteLifetimeMinutes.contains(lifetimeMinutes) else {
            throw MemberInviteError.invalidLifetime
        }
        guard memberLinks.count < MemberLinkStore.maxLinks else { throw MemberInviteError.linkLimit }
        let sourcePairing = connectionRegistry.preferred?.pairing
        let companyOnly = projectId.isEmpty
        guard companyOnly || sourcePairing != nil else { throw MemberInviteError.noComputer }
        let selected: Set<String>
        let deviceName: String
        if companyOnly {
            guard (projectIds ?? []).isEmpty else { throw MemberInviteError.invalidScope }
            selected = []
            deviceName = hubDisplayName
        } else {
            guard let snapshot = meshSnapshots[projectId], !ownComputerRooms(for: projectId).isEmpty
            else { throw MemberInviteError.noProject }
            selected = (projectIds ?? [projectId]).union([projectId])
            guard selected.count <= 16,
                  selected.allSatisfy({ meshSnapshots[$0] != nil && ($0 == projectId || !ownComputerRooms(for: $0).isEmpty) })
            else { throw MemberInviteError.invalidScope }
            deviceName = "\(hubDisplayName) · \(snapshot.project.name)"
        }
        guard let account = companyAccounts.first(where: { $0.id == accountId }), !account.disabled,
              selected.allSatisfy({ id in
                  meshSnapshots[id].map { CompanyAccountPolicy.canReceive($0, account: account) } == true
              }) else { throw MemberInviteError.invalidAccount }
        let hub: (publicKey: Data, secretKey: Data)
        let member: (publicKey: Data, secretKey: Data)
        do {
            hub = try NaclBox.keyPair()
            member = try NaclBox.keyPair()
        } catch {
            throw MemberInviteError.keyGeneration
        }
        let now = Date().timeIntervalSince1970 * 1_000
        let room = Self.hex(try Crypto.randomBytes(16))
        let pushAuth = Self.hex(try Crypto.randomBytes(32))
        let senderId = Self.hex(try Crypto.randomBytes(4))
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let relayURL = sourcePairing?.relayUrl ?? Pairing.currentRelaySocket
        let memberPairing = Pairing(
            relayUrl: relayURL, room: room, role: "phone",
            deviceName: deviceName, senderId: senderId,
            myPublicKey: member.publicKey.base64EncodedString(),
            mySecretKey: member.secretKey.base64EncodedString(),
            peerPublicKey: hub.publicKey.base64EncodedString(), pushAuth: pushAuth,
            hub: true, inviteKind: companyOnly ? "company" : "mesh"
        )
        let hubPairing = Pairing(
            relayUrl: relayURL, room: room, role: "machine",
            deviceName: deviceName, senderId: "hub-\(senderId)",
            myPublicKey: hub.publicKey.base64EncodedString(),
            mySecretKey: hub.secretKey.base64EncodedString(),
            peerPublicKey: member.publicKey.base64EncodedString(), pushAuth: pushAuth
        )
        let data = try JSONEncoder().encode(memberPairing)
        let transferKey = Self.base64URL(try Crypto.randomBytes(32))
        guard let sealed = Crypto.openableSeal(data, key: transferKey),
              let base = Pairing.normalizedPairingHTTPBase(relayURL),
              let url = URL(string: "\(base)/pair/\(Self.hex(try Crypto.randomBytes(16)))")
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
        guard status == 200 || status == 201 else { throw MemberInviteError.relayUnavailable }
        let inviteURI = Self.memberInviteURI(base: base, mailbox: url.lastPathComponent, key: transferKey)
        let link = MemberLink(
            id: room, projectId: projectId, name: cleanName.isEmpty ? L("Member") : cleanName,
            role: role, rules: rules, companyAccountId: accountId,
            sharedProjectIds: selected.sorted(), createdAt: now,
            inviteExpiresAt: now + Double(lifetimeMinutes) * 60_000,
            inviteURI: inviteURI, hubPairing: hubPairing
        )
        memberLinks.append(link)
        guard MemberLinkStore.save(memberLinks) else {
            memberLinks.removeAll { $0.id == room }
            throw MemberInviteError.storage
        }
        attachMemberLink(link)
        return inviteURI
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

    @discardableResult
    func updateMemberLink(_ link: MemberLink) -> Bool {
        guard let index = memberLinks.firstIndex(where: { $0.id == link.id }) else { return false }
        let before = memberLinks[index]
        guard link.projectId == before.projectId,
              link.companyAccountId == before.companyAccountId,
              link.projectIds.subtracting(before.projectIds).allSatisfy({
                  meshSnapshots[$0] != nil && !ownComputerRooms(for: $0).isEmpty
                      && memberCanAccessProject(link, projectId: $0)
              })
        else { return false }
        var updated = memberLinks
        updated[index] = link
        guard MemberLinkStore.save(updated) else { return false }
        memberLinks = updated
        if !before.projectIds.subtracting(link.projectIds).isEmpty {
            clearMemberPendingRoutes(for: link.id)
        }
        for removed in before.projectIds.subtracting(link.projectIds) {
            meshProjectSourceRooms[removed]?.remove(link.id)
        }
        for added in link.projectIds.subtracting(before.projectIds) {
            meshProjectSourceRooms[added, default: []].insert(link.id)
            if memberLinkConnected.contains(link.id) { forwardMemberProject(added, to: link) }
        }
        // Chats newly allowed are handed over at once, not on the next hello.
        if link.rules.canSeeChats, !before.rules.canSeeChats { forwardChatsToMember(link) }
        return true
    }

    @discardableResult
    func removeMemberLink(id: String) -> Bool {
        let remaining = memberLinks.filter { $0.id != id }
        guard remaining.count < memberLinks.count, MemberLinkStore.save(remaining) else { return false }
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
        clearMemberPendingRoutes(for: id)
        memberLinks = remaining
        return true
    }

    func clearMemberPendingRoutes(for linkId: String) {
        memberForwardedMessages = memberForwardedMessages.filter { $0.value != linkId }
        memberForwardedControls = memberForwardedControls.filter { $0.value != linkId }
        memberForwardedSets = memberForwardedSets.filter { $0.value != linkId }
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

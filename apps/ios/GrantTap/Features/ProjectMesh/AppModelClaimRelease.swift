import Foundation

/// What the person may do to a claim that no agent may.
///
/// A claim is released by its owner, and only its owner: that is what keeps
/// one agent from clearing another's hold on a file. It also means a claim
/// whose owner died, or will not let go, stays until it expires. The person
/// is not an owner and not bound by that rule; they are who the rule
/// protects. So a release from here is a command of its own, sent to each
/// computer of the Project, which writes down that it was used and answers.
/// From a member's phone the same command goes to the person whose Project
/// it is, who lets it through by the member's role and answers likewise, so
/// a refusal is seen where the release was made.
@MainActor
extension AppModel {
    @discardableResult
    func releaseClaimByPerson(projectId: String, claimId: String, reason: String? = nil) -> [String] {
        guard agentMeshPreferences.meshEnabled, !claimId.isEmpty else { return [] }
        let request = MeshClaimRelease(
            type: "mesh.claim.release", sessionId: projectId, projectId: projectId, claimId: claimId,
            reason: reason, requestId: UUID().uuidString.lowercased(), createdAt: Date().timeIntervalSince1970 * 1_000
        )
        let rooms = computerRooms(for: projectId).sorted()
        for room in rooms {
            relaysByRoom[room]?.sendSession(
                payload: request, sessionId: projectId, ttl: 15 * 60,
                deliveryId: "claim-release-\(claimId.prefix(32))-\(request.requestId ?? "")"
            )
        }
        claimReleaseNotices.removeValue(forKey: claimId)
        forgetClaim(claimId, projectId: projectId)
        append("claim \(claimId.prefix(8)) released by you → \(rooms.count) room(s)")
        return rooms
    }

    /// A member's release, by the member's role: on to this phone's own
    /// computers, remembered so their answer finds its way back.
    @discardableResult
    func forwardMemberClaimRelease(_ data: Data, link: MemberLink) -> [String] {
        guard let request = try? JSONDecoder().decode(MeshClaimRelease.self, from: data),
              request.isWellFormed, request.projectId == link.projectId else { return [] }
        let rooms = ownComputerRooms(for: link.projectId).sorted()
        guard !rooms.isEmpty else {
            refuseMemberRelease(request, link: link, reason: "no_computer")
            return []
        }
        memberForwardedReleases[Self.releaseKey(request.claimId, requestId: request.requestId)] = link.id
        for room in rooms {
            relaysByRoom[room]?.sendSession(
                payload: request, sessionId: request.projectId, ttl: 15 * 60,
                deliveryId: "member-claim-release-\(request.claimId.prefix(32))-\(link.id.prefix(8))"
            )
        }
        forgetClaim(request.claimId, projectId: link.projectId)
        append("member \(link.name) released claim \(request.claimId.prefix(8)) → \(rooms.count) room(s)")
        return rooms
    }

    static func releaseKey(_ claimId: String, requestId: String?) -> String {
        "\(claimId)\u{1f}\(requestId ?? "")"
    }

    /// A refusal the member's phone shows on the claim it tried to release.
    @discardableResult
    func refuseMemberRelease(_ request: MeshClaimRelease, link: MemberLink, reason: String, detail: String? = nil) -> MeshClaimReleaseResult {
        let result = MeshClaimReleaseResult(
            type: "mesh.claim.release.result", sessionId: request.projectId, projectId: request.projectId,
            claimId: request.claimId, ok: false, reason: reason, detail: detail, requestId: request.requestId,
            generatedAt: Date().timeIntervalSince1970 * 1_000
        )
        meshEndpointRelaysById[link.id]?.sendSession(payload: result, sessionId: request.projectId, ttl: 15 * 60)
        append("member \(link.name) refused: claim release (\(reason))")
        return result
    }

    /// A computer's answer to a release a member asked for goes to that member.
    @discardableResult
    func handOffReleaseResultToMember(_ result: MeshClaimReleaseResult) -> Bool {
        let key = Self.releaseKey(result.claimId, requestId: result.requestId)
        guard let linkId = memberForwardedReleases.removeValue(forKey: key),
              let client = meshEndpointRelaysById[linkId] else { return false }
        client.sendSession(payload: result, sessionId: result.projectId, ttl: 15 * 60)
        return true
    }

    /// What a computer, or the Project's owner, said about a release from here:
    /// done, and the claim stays gone; refused, and the claim comes back with
    /// the reason beside it.
    func receive(_ result: MeshClaimReleaseResult, fromRoom room: String) {
        guard agentMeshPreferences.meshEnabled, result.isWellFormed else { return }
        if handOffReleaseResultToMember(result) { return }
        if result.ok {
            releasedClaims.removeValue(forKey: result.claimId)
            claimReleaseNotices.removeValue(forKey: result.claimId)
            return
        }
        // Another computer of the same Project may still answer yes; a claim
        // one of them never had is not a refusal of the release.
        guard result.reason != "unknown_claim" else { return }
        meshReleasedClaims.removeValue(forKey: result.claimId)
        if let claim = releasedClaims.removeValue(forKey: result.claimId), var snapshot = meshSnapshots[result.projectId],
           !snapshot.claims.contains(where: { $0.claimId == claim.claimId }) {
            snapshot.claims.append(claim)
            meshSnapshots[result.projectId] = snapshot
            persistMeshState()
        }
        claimReleaseNotices[result.claimId] = result.message
        append("claim release refused (\(result.reason ?? "?")): \(result.message)")
        objectWillChange.send()
    }

    /// A released claim leaves this phone's own picture at once: snapshots
    /// merge claims by union, so a computer that dropped it would not take it
    /// away from here on its own. It is kept aside until the answer comes.
    func forgetClaim(_ claimId: String, projectId: String) {
        guard var snapshot = meshSnapshots[projectId],
              let claim = snapshot.claims.first(where: { $0.claimId == claimId }) else { return }
        releasedClaims[claimId] = claim
        // Until the claim would have expired anyway, it stays gone here: a
        // computer that was away when the release happened publishes what it
        // last knew, and claims merge by union.
        meshReleasedClaims[claimId] = claim.expiresAt
        snapshot.claims.removeAll { $0.claimId == claimId }
        meshSnapshots[projectId] = snapshot
        persistMeshState()
        objectWillChange.send()
    }

    /// A claim released from here, until its own expiry. What is past that is
    /// forgotten, because a claim of the same id made afterwards is a new one.
    func isReleasedClaim(_ claimId: String, at nowMs: Double) -> Bool {
        guard let until = meshReleasedClaims[claimId] else { return false }
        guard until > nowMs else {
            meshReleasedClaims.removeValue(forKey: claimId)
            return false
        }
        return true
    }

    /// Claims a release from here has taken away, dropped from what arrives.
    func withoutReleasedClaims(_ snapshot: ProjectMeshSnapshot, at nowMs: Double) -> ProjectMeshSnapshot {
        guard !meshReleasedClaims.isEmpty else { return snapshot }
        var kept = snapshot
        kept.claims = snapshot.claims.filter { !isReleasedClaim($0.claimId, at: nowMs) }
        return kept
    }
}

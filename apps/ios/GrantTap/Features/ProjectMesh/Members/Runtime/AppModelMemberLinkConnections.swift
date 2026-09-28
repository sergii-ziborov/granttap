import Foundation

@MainActor
extension AppModel {
    func attachStoredMemberLinks() {
        for link in memberLinks where link.joinedAt != nil
            || link.inviteExpiresAt > Date().timeIntervalSince1970 * 1_000 {
            attachMemberLink(link)
        }
    }

    func attachMemberLink(_ link: MemberLink) {
        // Account pairing is a controller-device operation. It must work before
        // a computer or Project exists, even when Project Mesh is disabled.
        guard agentMeshPreferences.meshEnabled || link.projectIds.isEmpty else { return }
        guard link.joinedAt != nil || link.inviteExpiresAt > Date().timeIntervalSince1970 * 1_000 else { return }
        meshEndpointRelaysById[link.id]?.disconnect()
        let client = RelayClient(pairing: link.hubPairing)
        meshEndpointRoomToId[link.id] = link.id
        meshEndpointRelaysById[link.id] = client
        for projectId in link.projectIds where memberCanAccessProject(link, projectId: projectId) {
            meshProjectSourceRooms[projectId, default: []].insert(link.id)
        }
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
            memberLinks[index].lastSeenAt = now
            MemberLinkStore.save(memberLinks)
            sendHubHeartbeat(linkId: linkId)
            memberHubTimers[linkId]?.invalidate()
            memberHubTimers[linkId] = Timer.scheduledTimer(
                withTimeInterval: Self.memberHeartbeatSeconds, repeats: true
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.sendHubHeartbeat(linkId: linkId) }
            }
            if memberLinks[index].joinedAt != nil { forwardProjectToMember(memberLinks[index]) }
        } else {
            memberLinkConnected.remove(linkId)
            memberLinks[index].lastSeenAt = now
            MemberLinkStore.save(memberLinks)
            memberHubTimers[linkId]?.invalidate()
            memberHubTimers.removeValue(forKey: linkId)
        }
    }

    /// A live owner socket is not a joined member. Only the paired phone's
    /// authenticated hello can claim a one-time invite before expiry.
    func memberPeerHello(linkId: String) {
        guard let index = memberLinks.firstIndex(where: { $0.id == linkId }) else { return }
        let now = Date().timeIntervalSince1970 * 1_000
        if memberLinks[index].joinedAt == nil {
            guard now < memberLinks[index].inviteExpiresAt else { return }
            var updated = memberLinks
            updated[index].joinedAt = now
            updated[index].inviteURI = nil
            guard MemberLinkStore.save(updated) else { return }
            memberLinks = updated
        }
        forwardProjectToMember(memberLinks[index])
    }

    func sendHubHeartbeat(linkId: String) {
        guard memberLinkConnected.contains(linkId), let client = meshEndpointRelaysById[linkId] else { return }
        client.send(payload: HubHeartbeat(machine: hubDisplayName, createdAt: Date().timeIntervalSince1970 * 1_000), ttl: 60)
    }

    /// What the member's phone needs first: the Project as it stands and its
    /// Governance, from a computer that holds the Project's key, and the
    /// Project's chats when the member may see them.
    func forwardProjectToMember(_ link: MemberLink) {
        guard link.joinedAt != nil else { return }
        for projectId in link.projectIds.sorted() where memberCanAccessProject(link, projectId: projectId) {
            forwardMemberProject(projectId, to: link)
        }
        forwardChatsToMember(link)
    }

    func forwardMemberProject(_ projectId: String, to link: MemberLink) {
        guard link.joinedAt != nil, memberCanAccessProject(link, projectId: projectId),
              let source = ownComputerRooms(for: projectId).sorted().first else { return }
        if let snapshot = meshSnapshots[projectId] {
            forwardMesh(snapshot, scopeId: projectId, purpose: "project", sourceRoom: source, targetRoom: link.id)
        }
        if let status = projectGovernance[projectId]?.wireStatus() {
            forwardMesh(status, scopeId: projectId, purpose: "project", sourceRoom: source, targetRoom: link.id)
        }
    }

}

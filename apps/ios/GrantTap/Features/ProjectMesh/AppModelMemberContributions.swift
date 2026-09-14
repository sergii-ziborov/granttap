import Foundation

/// What a member's side brings into the mesh, and what of it this phone takes.
///
/// A member's phone forwards the Project as it sees it — its own computers'
/// work, and a copy of everyone else's that this phone handed it. The copy is
/// not an authority, so each row is bound to the member's phone that first
/// spoke for it, and what another member already speaks for is left alone.
@MainActor
extension AppModel {
    /// A member's own computer, brought into the Project: its snapshot joins
    /// the mesh here like any computer's, and goes on to the others — but
    /// only the part of it the member's side may speak for.
    @discardableResult
    func acceptMemberSnapshot(_ data: Data, link: MemberLink) -> Bool {
        guard ProjectMeshWireValidator.validSnapshot(data),
              let snapshot = try? JSONDecoder().decode(ProjectMeshSnapshot.self, from: data),
              snapshot.projectId == link.projectId else { return false }
        let contribution = MemberContribution.filtered(
            snapshot, known: meshSnapshots[link.projectId], rules: link.rules,
            owned: ownedInProject(link.projectId), speakingFor: link.id
        )
        rememberMemberContribution(contribution, room: link.id)
        receive(contribution, fromRoom: link.id)
        return true
    }

    /// What this member spoke for, so the next member cannot speak for it.
    func rememberMemberContribution(_ snapshot: ProjectMeshSnapshot, room: String) {
        for key in MemberContribution.rowKeys(of: snapshot) where meshContributionRooms[key] == nil {
            meshContributionRooms[key] = room
        }
        guard meshContributionRooms.count > Self.maxMemberContributionRows else { return }
        // Bounded like every other map the phone keeps for the mesh: the rows
        // still in the Project are kept, and what no snapshot mentions goes.
        let live = Set(meshSnapshots.values.flatMap { MemberContribution.rowKeys(of: $0) })
        meshContributionRooms = meshContributionRooms.filter { live.contains($0.key) }
    }

    static let maxMemberContributionRows = 4_096

    /// What this phone's own computers hold in a Project: their chats, and the
    /// names they publish under.
    func ownedInProject(_ projectId: String) -> MemberContribution.Owned {
        let rooms = ownComputerRooms(for: projectId)
        var names: Set<String> = []
        for connection in connectionRegistry.connections where rooms.contains(connection.id) {
            let published = connection.lastMachineName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !published.isEmpty { names.insert(published) }
            names.insert(connection.displayName)
        }
        return MemberContribution.Owned(
            isOwnChat: { [weak self] sessionId in self?.isOwnComputerChat(sessionId, projectId: projectId) ?? false },
            ownComputers: names,
            contributor: { [weak self] key in self?.meshContributionRooms[key] }
        )
    }

    /// A member's Mesh event: inside its Project, of a kind the member's rules
    /// allow, and never in the name of a chat on this phone's own computers.
    @discardableResult
    func acceptMemberEvent(_ data: Data, link: MemberLink) -> Bool {
        guard ProjectMeshWireValidator.validEvent(data),
              let event = try? JSONDecoder().decode(ProjectMeshEvent.self, from: data),
              event.projectId == link.projectId,
              MemberHubPolicy.allowsEvent(event.eventType, rules: link.rules),
              !isOwnComputerChat(event.sourceSessionId, projectId: link.projectId),
              // Nor in the name of a chat another member's phone speaks for.
              meshContributionRooms[MemberContribution.chatKey(event.sourceSessionId)].map({ $0 == link.id }) ?? true
        else { return false }
        receive(event, fromRoom: link.id)
        return true
    }

    /// A chat that one of this phone's own computers reported: nobody else
    /// may publish as it.
    func isOwnComputerChat(_ sessionId: String, projectId: String) -> Bool {
        guard let room = sourceRoom(forSessionId: sessionId) else { return false }
        return ownComputerRooms(for: projectId).contains(room)
    }

    /// A member's hand-off of a Task from one of the Project's chats: sent to
    /// the computer that holds the chat, and authorised here the way this
    /// phone's own hand-offs are, so the request the computer publishes is
    /// forwarded to its destination instead of waiting for a person.
    @discardableResult
    func forwardMemberHandoff(_ data: Data, link: MemberLink) -> Bool {
        guard let request = try? JSONDecoder().decode(ProjectMeshHandoffPrepare.self, from: data),
              request.type == "mesh.handoff.prepare",
              request.projectId == link.projectId,
              agentMeshPreferences.isProviderEnabled(request.targetProvider) || request.targetProvider == "grok_bot",
              isProjectChat(request.sessionId, projectId: link.projectId),
              let room = sourceRoom(forSessionId: request.sessionId),
              let relay = relaysByRoom[room] else { return false }
        authorizedHandoffRoutes[request.taskId] = Self.handoffRoute(
            provider: request.targetProvider, computer: request.targetComputer
        )
        relay.send(payload: request, ttl: 15 * 60) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.authorizedHandoffRoutes[request.taskId] = nil }
        }
        return true
    }
}

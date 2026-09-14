import TweetNacl
import XCTest
@testable import GrantTap

/// One phone that owns a Project, one computer of its own, one Project shared
/// with it by someone else, and one member it shares with. The tests about
/// members all start here, so they start from the same place.
@MainActor
enum MemberHubFixture {
    static let own = String(repeating: "a", count: 32)
    static let hubRoom = String(repeating: "h", count: 32)
    static let linkRoom = String(repeating: "b", count: 32)

    static func pairing(role: String, room: String, hub: Bool? = nil) throws -> Pairing {
        let me = try NaclBox.keyPair()
        let peer = try NaclBox.keyPair()
        return Pairing(
            relayUrl: "wss://relay.granttap.app", room: room, role: role,
            deviceName: hub == true ? "Olga's iPhone · GrantTap" : "Mac", senderId: "s",
            myPublicKey: me.publicKey.base64EncodedString(), mySecretKey: me.secretKey.base64EncodedString(),
            peerPublicKey: peer.publicKey.base64EncodedString(), hub: hub
        )
    }

    static func session(_ id: String, project: String?) -> SessionInfo {
        SessionInfo(sessionId: id, agent: "claude", projectId: project, taskId: project.map { "task-\($0)" },
                    computerId: "Mac", title: "Chat \(id)", state: "idle",
                    startedAt: 1, lastActivityAt: 2, tokensSession: 1, tokensLastTurn: 1)
    }

    static func snapshot(_ projectId: String = "project") -> ProjectMeshSnapshot {
        ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: projectId, projectId: projectId,
            project: ProjectMeshProject(projectId: projectId, name: "GrantTap", repositoryRoot: "/repo",
                                        canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
    }

    /// This phone with one computer of its own, one Project shared with it
    /// by someone else, and one member it shares with.
    static func hub(rules: MemberRules = .preset(.member)) throws -> (AppModel, MemberLink) {
        let model = AppModel()
        model.memberLinks = []
        model.agentMeshPreferences.meshEnabled = true
        let mac = try pairing(role: "phone", room: own)
        let theirPhone = try pairing(role: "phone", room: hubRoom, hub: true)
        var registry = ConnectionRegistryLogic.upsert(.empty, pairing: mac, mode: .add, prefer: true)
        registry = ConnectionRegistryLogic.upsert(registry, pairing: theirPhone, mode: .add, prefer: false)
        model.connectionRegistry = registry
        model.relaysByRoom[own] = RelayClient(pairing: mac)
        model.sessions = [session("s1", project: "project"), session("s2", project: "other"), session("s3", project: "project")]
        model.sessionHistory = [session("h1", project: "project")]
        model.rememberSessionSourceRooms(own, sessionIds: ["s1", "s2", "h1"])
        model.rememberSessionSourceRoom(hubRoom, sessionId: "s3")
        model.meshProjectSourceRooms["project"] = [own, hubRoom]
        model.meshProjectSourceRooms["other"] = [own]
        model.meshSnapshots = ["project": snapshot(), "other": snapshot("other")]
        let link = MemberLink(
            id: linkRoom, projectId: "project", name: "Olga", role: .member, rules: rules, createdAt: 1_000,
            inviteExpiresAt: 2_000, joinedAt: 1_500, hubPairing: try pairing(role: "machine", room: linkRoom)
        )
        model.memberLinks = [link]
        model.meshEndpointRelaysById[link.id] = RelayClient(pairing: link.hubPairing)
        model.meshEndpointRoomToId[link.id] = link.id
        model.meshProjectSourceRooms["project"]?.insert(link.id)
        model.memberLinkConnected.insert(link.id)
        return (model, link)
    }
}

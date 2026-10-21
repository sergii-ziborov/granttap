import XCTest
import SwiftUI
@testable import GrantTap

@MainActor
final class KnowledgeRefreshTests: XCTestCase {
    private func fixture() -> AppModel {
        let model = AppModel()
        model.sessions = []
        model.meshSnapshots = ["project": ProjectMeshSnapshot(type: "mesh.snapshot",
            sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "Project", canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [.init(taskId: "task", projectId: "project", title: "Task", goal: "", state: "working",
                          ownerSessionId: nil, createdAt: 1, updatedAt: 2)],
            executions: [], claims: [], dependencies: [], events: [], generatedAt: 2)]
        model.meshProjectSourceRooms = ["project": ["room"]]
        model.roomRuntime["room"] = .init(socketUp: true)
        let pairing = Pairing(relayUrl: "ws://127.0.0.1:1", room: "room", role: "phone",
            deviceName: "Workstation", senderId: "test", myPublicKey: "public",
            mySecretKey: "secret", peerPublicKey: "peer")
        model.relaysByRoom["room"] = RelayClient(pairing: pairing)
        return model
    }

    func testReopeningKnowledgeRequeriesAnAlreadyLoadedTailAndWaitsForFreshSnapshot() async throws {
        let model = fixture()
        let key = AppModel.invocationTaskKey("project", "task")
        model.invocationRequestedTasks.insert(key)
        model.invocationAvailabilityByTask[key] = "ready"
        let sync = ProjectKnowledgeRefresh(timeout: 2, pollNanoseconds: 1_000_000)
        let job = Task { await sync.refresh(projectId: "project", model: model) }
        for _ in 0..<100 where model.invocationPendingRooms.isEmpty {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let request = try XCTUnwrap(model.invocationPendingRooms.keys.first)
        XCTAssertEqual(sync.state, .loading)
        XCTAssertEqual(model.invocationAvailabilityByTask[key], "loading")
        let saved = try XCTUnwrap(model.meshSnapshots["project"])
        var wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        wire["generatedAt"] = 3
        let fresh = try JSONDecoder().decode(ProjectMeshSnapshot.self, from: JSONSerialization.data(withJSONObject: wire))
        model.meshSnapshots["project"] = fresh
        model.receiveInvocationPage(.init(type: "mesh.invocation.page", sessionId: "project",
            projectId: "project", taskId: "task", requestId: request, sourceEndpointId: "computer",
            availability: "ready", events: [], nextSequence: 0, previousSequence: 0,
            hasMore: false, hasOlder: false, generatedAt: 3), fromRoom: "room")
        await job.value
        XCTAssertEqual(sync.state, .updated)
        XCTAssertEqual(model.meshSnapshots["project"]?.generatedAt, 3)
        XCTAssertTrue(model.invocationPendingRooms.isEmpty)
    }

    func testDifferentMeshesOnTheSameComputerHaveIndependentRefreshIdentities() throws {
        let model = fixture()
        let first = try XCTUnwrap(model.meshSnapshots["project"])
        let other = ProjectMeshSnapshot(type: "mesh.snapshot", sessionId: "other", projectId: "other",
            project: .init(projectId: "other", name: "Other", canonicalRepositoryId: "other-repo", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 2)
        model.meshProjectSourceRooms["other"] = ["room"]
        XCTAssertNotEqual(ProjectKnowledgeView(snapshot: first, model: model).connectionKey,
                          ProjectKnowledgeView(snapshot: other, model: model).connectionKey)
    }

    func testTimeoutKeepsSavedSnapshotAndDoesNotClaimItWasRefreshed() async {
        let model = fixture()
        let saved = model.meshSnapshots["project"]
        let sync = ProjectKnowledgeRefresh(timeout: 0.01, pollNanoseconds: 1_000_000)
        await sync.refresh(projectId: "project", model: model)
        XCTAssertEqual(sync.state, .unavailable)
        XCTAssertEqual(model.meshSnapshots["project"], saved)
        if let saved { RenderProbe.render(NavigationView { ProjectKnowledgeView(snapshot: saved, model: model) }) }
    }

    func testExpiredQueryCanBeRetriedAndCannotAcceptALateReplyGeneration() {
        let model = fixture()
        let taskKey = AppModel.invocationTaskKey("project", "task")
        model.requestInvocationHistory(projectId: "project", taskId: "task")
        let requests = model.invocationPendingRooms
        XCTAssertEqual(requests.count, 1)
        for (id, roomKey) in requests {
            model.expireInvocationRequest(id, taskKey: taskKey, roomKey: "wrong-room")
            XCTAssertNotNil(model.invocationPendingRooms[id])
            model.expireInvocationRequest(id, taskKey: taskKey, roomKey: roomKey)
        }
        XCTAssertTrue(model.invocationPendingRooms.isEmpty)
        XCTAssertFalse(model.invocationRequestedTasks.contains(taskKey))
        XCTAssertEqual(model.invocationAvailabilityByTask[taskKey], "unavailable")
        model.requestInvocationHistory(projectId: "project", taskId: "task")
        XCTAssertEqual(model.invocationPendingRooms.count, 1)
        XCTAssertNotEqual(Set(model.invocationPendingRooms.keys), Set(requests.keys))
    }

    func testOfflineAndCancellationKeepSavedEvidence() async {
        let model = fixture()
        model.roomRuntime["room"]?.socketUp = false
        let sync = ProjectKnowledgeRefresh(timeout: 1)
        await sync.refresh(projectId: "project", model: model)
        XCTAssertEqual(sync.state, .unavailable)
        model.roomRuntime["room"]?.socketUp = true
        let job = Task { await sync.refresh(projectId: "project", model: model) }
        await Task.yield()
        job.cancel()
        await job.value
        XCTAssertNotEqual(sync.state, .loading)
        XCTAssertEqual(model.meshSnapshots["project"]?.generatedAt, 2)
    }
}

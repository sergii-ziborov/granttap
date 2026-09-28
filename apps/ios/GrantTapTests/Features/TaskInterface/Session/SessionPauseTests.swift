import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class SessionPauseTests: XCTestCase {
    private func session(_ id: String, paused: Bool? = nil) -> SessionInfo {
        var session = SessionInfo(sessionId: id, agent: "claude", projectId: "p", taskId: "t", title: "Held chat",
                                  cwd: "/repo", state: "working", startedAt: 1, lastActivityAt: 2, tokensSession: 1, tokensLastTurn: 1)
        session.paused = paused
        return session
    }

    func testTheWireCarriesAHoldAndItsAnswer() throws {
        let held = try JSONDecoder().decode(SessionInfo.self, from: Data("""
        {"sessionId":"s","agent":"claude","state":"working","startedAt":1,"lastActivityAt":2,"tokensSession":0,"tokensLastTurn":0,"paused":true}
        """.utf8))
        XCTAssertTrue(held.isPaused)
        let free = try JSONDecoder().decode(SessionInfo.self, from: Data("""
        {"sessionId":"s","agent":"claude","state":"working","startedAt":1,"lastActivityAt":2,"tokensSession":0,"tokensLastTurn":0}
        """.utf8))
        XCTAssertFalse(free.isPaused)
        XCTAssertNil(free.paused)

        let pause = SessionControl(type: "session.control", sessionId: "s", action: "pause", createdAt: 3)
        let encoded = try RelayClient.encodeOmittingNulls(pause)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["continue"], "an absent flag is absent, not null, on the wire")
        let resume = SessionControl(type: "session.control", sessionId: "s", action: "resume", continue: true, createdAt: 3)
        XCTAssertEqual(resume.continue, true)
        XCTAssertEqual(RelayClient.sessionPayloadCoalescingKey(encoded), RelayClient.SessionPayloadCoalescingKey.control)

        let client = RelayClient(pairing: PairingFixture.pairing(room: "pause-inbound"))
        var received: [SessionControlResult] = []
        let delivered = expectation(description: "result")
        client.onSessionControlResult = { (result: SessionControlResult) in
            received.append(result)
            delivered.fulfill()
        }
        let result = SessionControlResult(type: "session.control.result", sessionId: "s", action: "pause", ok: true, message: "Paused", createdAt: 4)
        XCTAssertTrue(client.handlePlain(try JSONEncoder().encode(result)))
        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(received.first?.action, "pause")
        let odd = SessionControlResult(type: "session.control.result", sessionId: "s", action: "stop", ok: true, message: "?", createdAt: 4)
        XCTAssertFalse(client.handlePlain(try JSONEncoder().encode(odd)), "only pause and resume are answers")
    }

    func testTheModelHoldsAndReleasesAChat() throws {
        let model = AppModel()
        let room = "pause-\(UUID().uuidString)"
        let client = RelayClient(pairing: PairingFixture.pairing(room: room))
        model.sessions = [session("s")]
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: PairingFixture.pairing(room: room))
        model.relaysByRoom[room] = client
        model.rememberSessionSourceRoom(room, sessionId: "s")

        model.pauseSession("s")
        XCTAssertTrue(model.sessionControlPending.contains("s"))
        XCTAssertEqual(model.sessions.first?.isPaused, true, "the phone shows the hold before the computer confirms")
        model.pauseSession("s")
        model.resumeSession("s")
        XCTAssertEqual(model.sessions.first?.isPaused, true, "one request at a time")

        model.receive(SessionControlResult(type: "session.control.result", sessionId: "s", action: "pause", ok: true, message: "Paused.", createdAt: 5))
        XCTAssertFalse(model.sessionControlPending.contains("s"))
        XCTAssertEqual(model.sessionControlResults["s"]?.message, "Paused.")
        model.resumeSession("s")
        XCTAssertEqual(model.sessions.first?.isPaused, false)
        model.receive(SessionControlResult(type: "session.control.result", sessionId: "s", action: "resume", ok: false, message: "No.", createdAt: 6))
        XCTAssertEqual(model.sessions.first?.isPaused, true, "a resume the computer refused leaves the chat held, as it is")
        XCTAssertTrue(model.log.contains { $0.contains("No.") })

        model.pauseSession("unknown")
        XCTAssertTrue(model.sessionControlPending.contains("unknown"), "with one computer paired, the request goes there")
        let lonely = AppModel()
        lonely.pauseSession("nowhere")
        XCTAssertTrue(lonely.log.contains { $0.contains("pause blocked") })
    }

    /// A hold is what the computer does, not what the phone hoped for.
    func testAHoldNobodyConfirmedIsTakenBack() async throws {
        let model = AppModel()
        let room = "pause-timeout-\(UUID().uuidString)"
        model.sessions = [session("s")]
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: PairingFixture.pairing(room: room))
        model.relaysByRoom[room] = RelayClient(pairing: PairingFixture.pairing(room: room))
        model.rememberSessionSourceRoom(room, sessionId: "s")
        let previous = AppModel.sessionControlTimeout
        AppModel.sessionControlTimeout = 10_000_000
        defer { AppModel.sessionControlTimeout = previous }

        model.pauseSession("s")
        XCTAssertEqual(model.sessions.first?.isPaused, true, "the screen answers the tap")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(model.sessionControlPending.contains("s"))
        XCTAssertEqual(model.sessions.first?.isPaused, false, "nobody confirmed it, so the guess is taken back")
        XCTAssertEqual(model.sessionControlResults["s"]?.ok, false)
        XCTAssertFalse(try XCTUnwrap(model.sessionControlResults["s"]?.message).isEmpty)

        // Confirmed, the hold stands, and a later silence does not undo it.
        model.pauseSession("s")
        model.receive(SessionControlResult(type: "session.control.result", sessionId: "s", action: "pause",
                                           ok: true, message: "Paused.", createdAt: 9))
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(model.sessions.first?.isPaused, true)
    }

    func testTheChatOffersPauseResumeHandoffAndReport() {
        let model = AppModel()
        let room = "pause-ui-\(UUID().uuidString)"
        model.sessions = [session("s", paused: true)]
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: PairingFixture.pairing(room: room))
        model.rememberSessionSourceRoom(room, sessionId: "s")
        let snapshot = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "p", projectId: "p",
            project: .init(projectId: "p", name: "nodvox", repositoryRoot: "/repo", canonicalRepositoryId: "github.com/x/nodvox", createdAt: 1),
            tasks: [.init(taskId: "t", projectId: "p", title: "Held", goal: "g", state: "working", ownerSessionId: "s", createdAt: 1, updatedAt: 2)],
            executions: [.init(taskId: "t", sessionId: "s", provider: "claude", computerId: "Mac", workspace: "/repo", startedAt: 1)],
            claims: [], dependencies: [], events: [], generatedAt: 2
        )
        model.meshSnapshots = ["p": snapshot]

        let paused = TaskChatView(session: session("s", paused: true), modelOverride: model)
        XCTAssertEqual(paused.chatSendAvailability?.blocksSending, true)
        XCTAssertTrue(paused.canHandOff)
        if case .task(_, let task) = paused.reportScope { XCTAssertEqual(task.taskId, "t") } else { XCTFail("a chat in a Task reports the Task") }
        XCTAssertFalse(paused.controlPending)
        RenderProbe.render(NavigationView { paused.environmentObject(model) })
        RenderProbe.render(NavigationView { paused.taskControlsMenu })
        RenderProbe.render(paused.taskStatusStrip)

        model.sessions = [session("s")]
        model.sessionControlPending.insert("s")
        let resuming = TaskChatView(session: session("s"), modelOverride: model)
        XCTAssertTrue(resuming.controlPending)
        XCTAssertNil(resuming.chatSendAvailability?.message.range(of: "Paused"))
        RenderProbe.render(resuming.taskStatusStrip)
        RenderProbe.render(NavigationView { resuming.taskControlsMenu })

        var loose = session("loose")
        loose.projectId = nil
        loose.taskId = nil
        let alone = TaskChatView(session: loose, modelOverride: model)
        XCTAssertFalse(alone.canHandOff)
        if case .chat(let chat) = alone.reportScope { XCTAssertEqual(chat.sessionId, "loose") } else { XCTFail("a chat outside a Task reports itself") }
        RenderProbe.render(NavigationView { alone.taskControlsMenu })
    }
}

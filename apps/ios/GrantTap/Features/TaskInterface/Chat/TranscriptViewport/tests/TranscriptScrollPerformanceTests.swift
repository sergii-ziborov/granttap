import XCTest
@testable import GrantTap

@MainActor
final class TranscriptScrollPerformanceTests: XCTestCase {
    func testScrollReadsReusePreparedRequestsAndTaskEvents() {
        let model = AppModel()
        model.demoMode = true
        var session = AppModelDemoFixtures.sessions(at: 100_000)[0]
        session.taskId = "scroll-task"
        model.sessions = [session]
        model.activities = [session.sessionId: DemoLongTranscript.activity(
            sessionId: session.sessionId, at: 100_000)]
        var snapshot = AppModelDemoMeshFixtures.linkedSnapshot(at: 100_000)
        snapshot.events = (0..<2_000).map { i in
            ProjectMeshEvent(type: "mesh.event", sessionId: session.sessionId,
                eventId: "event-\(i)", projectId: snapshot.projectId,
                taskId: i % 2 == 0 ? "scroll-task" : "another-task",
                sourceSessionId: session.sessionId, eventType: "STATUS", createdAt: Double(i),
                payload: .init(summary: "Observed progress \(i)"))
        }
        model.meshSnapshots = [snapshot.projectId: snapshot]
        let chat = TaskChatView(session: session, modelOverride: model)
        let expected = chat.timelineRows.count
        XCTAssertEqual(chat.previousUserEntry?.id, "long-4990")
        let start = ProcessInfo.processInfo.systemUptime
        var reads = 0
        for _ in 0..<120 {
            reads += chat.timelineRows.count
            XCTAssertEqual(chat.previousUserEntry?.id, "long-4990")
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        XCTAssertEqual(reads, expected * 120)
        let evidence = XCTAttachment(string: "120 scroll reads; 5000 messages, 2000 Mesh events: \(elapsed) seconds")
        evidence.name = "Transcript scroll preparation time"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertLessThan(elapsed, 0.15,
                         "Scrolling must reuse the request index and Task event projection.")
    }
}

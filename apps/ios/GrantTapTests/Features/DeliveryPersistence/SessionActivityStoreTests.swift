import XCTest
@testable import GrantTap

/// The phone keeps the chats it has been shown, so reopening one does not wait
/// on the Mac to re-send and decrypt a transcript the device already had.
final class SessionActivityStoreTests: XCTestCase {
    override func tearDown() {
        SessionActivityPersistence.clear()
        super.tearDown()
    }

    private func entry(_ index: Int) -> ActivityEntry {
        ActivityEntry(
            id: "entry-\(index)", kind: "message", text: "line \(index)",
            createdAt: Double(index)
        )
    }

    private func activity(
        _ sessionId: String, entries: Int, generatedAt: Double
    ) -> SessionActivity {
        SessionActivity(
            sessionId: sessionId, agent: "claude", state: "idle",
            entries: (0..<entries).map(entry), generatedAt: generatedAt
        )
    }

    func testATranscriptSurvivesARelaunch() {
        let stored = ["chat": activity("chat", entries: 3, generatedAt: 10)]
        SessionActivityPersistence.save(stored)

        let restored = SessionActivityPersistence.load()
        XCTAssertEqual(restored["chat"]?.entries.map(\.id), ["entry-0", "entry-1", "entry-2"])
        XCTAssertEqual(restored["chat"]?.agent, "claude")
    }

    func testOnlyTheNewestChatsAreKept() {
        // A phone accumulates chats forever; their transcripts must not.
        let many = Dictionary(uniqueKeysWithValues: (0..<80).map { index in
            ("chat-\(index)", activity("chat-\(index)", entries: 1, generatedAt: Double(index)))
        })
        let bounded = SessionActivityPersistence.bounded(many)
        XCTAssertEqual(bounded.count, SessionActivityPersistence.maxSessions)
        // The oldest fall out, the newest stay.
        XCTAssertNil(bounded["chat-0"])
        XCTAssertNotNil(bounded["chat-79"])
    }

    func testALongChatKeepsItsMostRecentExchange() {
        let long = activity("chat", entries: 400, generatedAt: 1)
        let bounded = SessionActivityPersistence.bounded(["chat": long])
        let kept = try? XCTUnwrap(bounded["chat"]).entries
        XCTAssertEqual(kept?.count, SessionActivityPersistence.maxEntriesPerSession)
        // Truncation is from the front: reopening a chat shows where it left off.
        XCTAssertEqual(kept?.last?.id, "entry-399")
        XCTAssertEqual(kept?.first?.id, "entry-100")
    }

    func testNoStoredFileIsAnEmptyStartRatherThanAFailure() {
        SessionActivityPersistence.clear()
        XCTAssertEqual(SessionActivityPersistence.load().count, 0)
    }

    @MainActor
    func testAppliedActivityIsOnDiskForTheNextLaunch() {
        SessionActivityPersistence.clear()
        let model = AppModel()
        model.applyActivity(activity("applied", entries: 2, generatedAt: 5))
        XCTAssertEqual(SessionActivityPersistence.load()["applied"]?.entries.count, 2)
    }
}

extension SessionActivityStoreTests {
    /// The computer sends a short window each time; merging them must not grow
    /// a chat without end.
    @MainActor
    func testMergingWindowsStopsAtTheKeptWindow() {
        let cap = SessionActivityPersistence.maxEntriesPerSession
        let existing = SessionActivity(
            sessionId: "chat", agent: "claude", state: "idle",
            entries: (0..<cap).map(entry), generatedAt: 1
        )
        let incoming = SessionActivity(
            sessionId: "chat", agent: "claude", state: "idle",
            entries: (cap..<(cap + 40)).map(entry), generatedAt: 2
        )
        let merged = AppModel.mergeActivity(existing: existing, incoming: incoming)
        XCTAssertEqual(merged.entries.count, cap)
        // Cut from the front: the newest exchange is the part being read.
        XCTAssertEqual(merged.entries.last?.id, "entry-\(cap + 39)")
        XCTAssertEqual(merged.entries.first?.id, "entry-40")
    }
}

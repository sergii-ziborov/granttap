import XCTest
@testable import GrantTap

final class TranscriptArchiveWriterTests: XCTestCase {
    @MainActor
    func testBackgroundWakeIsAcknowledgedOnlyAfterCompleteTranscriptIsDurable() async {
        SessionActivityPersistence.clear()
        defer { SessionActivityPersistence.clear() }
        let model = AppModel()
        let activity = snapshot("wake-history", revision: 10)
        let saved = expectation(description: "Durable history before background completion")
        model.backgroundWakeCompletions[UUID()] = { result in
            XCTAssertEqual(result, .newData)
            XCTAssertEqual(SessionActivityPersistence.load()[activity.sessionId], activity)
            saved.fulfill()
        }
        model.applyActivity(activity)
        await fulfillment(of: [saved], timeout: 5)
    }

    func testSlowDiskDoesNotBlockCallerAndLatestWholeHistoryWins() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = TranscriptArchive(directory: directory)
        defer { try? archive.clear() }
        let started = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let writer = TranscriptArchiveWriter { activity in
            XCTAssertFalse(Thread.isMainThread)
            if activity.generatedAt == 1 {
                started.signal()
                XCTAssertEqual(resume.wait(timeout: .now() + 5), .success)
            }
            do { try archive.save(activity) }
            catch { XCTFail("Snapshot write failed: \(error)") }
        }
        writer.enqueue(["chat": snapshot("chat", revision: 1)])
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        // The first write is still blocked, but UI callers can enqueue both chats.
        for version in 2...8 { writer.enqueue(["chat": snapshot("chat", revision: version)]) }
        writer.enqueue(["another": snapshot("another", revision: 9)])
        resume.signal()
        let restored = writer.barrier { archive.load() }
        XCTAssertEqual(restored["chat"], snapshot("chat", revision: 8))
        XCTAssertEqual(restored["another"], snapshot("another", revision: 9))
        XCTAssertEqual(restored["chat"]?.entries.count, 5_000)
        XCTAssertEqual(restored["chat"]?.entries.first?.id, "entry-0")
        XCTAssertEqual(restored["chat"]?.entries.last?.images?.first?.id, "retained-image")
        XCTAssertEqual(restored["chat"]?.history?.cursor, "older-native-page")
        writer.barrier { try? archive.clear() }
        XCTAssertTrue(writer.barrier { archive.load() }.isEmpty)
        let finished = expectation(description: "Background drain completed")
        writer.finish { finished.fulfill() }
        wait(for: [finished], timeout: 2)
    }

    private func snapshot(_ id: String, revision: Int) -> SessionActivity {
        var entries = (0..<5_000).map {
            ActivityEntry(id: "entry-\($0)", kind: "message", text: "Saved line", createdAt: Double($0))
        }
        entries[4_999].images = [.init(id: "retained-image", name: "saved.png", markdown: "![saved](granttap-image:retained-image)")]
        return SessionActivity(sessionId: id, agent: "codex", state: "idle", entries: entries,
                               generatedAt: Double(revision),
                               history: .init(cursor: "older-native-page", hasMore: true))
    }
}

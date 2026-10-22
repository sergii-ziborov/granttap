import XCTest
@testable import GrantTap

final class ReplicaImageRetentionTests: XCTestCase {
    func testCleanupExpiresOldBytesKeepsRecentPicturesAndTheirHistoricalRoutes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ReplicaImageStore(directory: folder)
        defer { store.clear() }
        store.remember(.init(sessionId: "chat", imageId: "old", cursor: "historical-page"), scope: "computer")
        try store.save(Data([1]), scope: "computer", sessionId: "chat", imageId: "old")
        try store.save(Data([2]), scope: "computer", sessionId: "chat", imageId: "recent")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let old = try XCTUnwrap(files.first { (try? Data(contentsOf: $0)) == Data([1]) })
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-40 * 86_400)],
                                               ofItemAtPath: old.path)
        XCTAssertEqual(store.prune(retention: .month), 1)
        XCTAssertNil(store.load(scope: "computer", sessionId: "chat", imageId: "old"))
        XCTAssertEqual(store.load(scope: "computer", sessionId: "chat", imageId: "recent"), Data([2]))
        XCTAssertEqual(store.cursor(scope: "computer", sessionId: "chat", imageId: "old"), "historical-page")
        store.remember(.init(sessionId: "chat", imageId: "old", cursor: "correct-page"),
                       scope: "computer", authoritative: true)
        XCTAssertEqual(store.cursor(scope: "computer", sessionId: "chat", imageId: "old"), "correct-page")
    }

    func testByteLimitEvictsLeastRecentlyUsedPicturesAndUntilFullDisablesAgeExpiry() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ReplicaImageStore(directory: folder)
        defer { store.clear() }
        for id in ["first", "second", "third"] {
            try store.save(Data(id.utf8), scope: "computer", sessionId: "chat", imageId: id)
        }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        for file in files {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-100 * 86_400)],
                                                   ofItemAtPath: file.path)
        }
        _ = store.load(scope: "computer", sessionId: "chat", imageId: "third")
        XCTAssertEqual(store.prune(retention: .unlimited, maximumBytes: 5), 2)
        XCTAssertEqual(store.bytes, 5)
        XCTAssertEqual(store.load(scope: "computer", sessionId: "chat", imageId: "third"), Data("third".utf8))
        XCTAssertNil(store.load(scope: "computer", sessionId: "chat", imageId: "first"))
        XCTAssertNil(store.load(scope: "computer", sessionId: "chat", imageId: "second"))
        store.clear()
        XCTAssertEqual(store.prune(), 0)
    }
}

import XCTest
@testable import GrantTap

final class ReplicaDocumentStoreTests: XCTestCase {
    func testDocumentsSurviveReopeningAndStayInsideTheirComputerAndConversation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = AttachmentDraft(name: "../Pasted.md", mimeType: "text/markdown", data: Data("# Document".utf8))
        try ReplicaDocumentStore(directory: folder).save([file], scope: "computer-a", sessionId: "chat-a", entryId: "row")
        let reopened = ReplicaDocumentStore(directory: folder)
        XCTAssertEqual(reopened.names(scope: "computer-a", sessionId: "chat-a", entryId: "row"), [file.name])
        XCTAssertEqual(reopened.load(scope: "computer-a", sessionId: "chat-a", entryId: "row", name: file.name)?.data,
                       file.data)
        XCTAssertNil(reopened.load(scope: "computer-b", sessionId: "chat-a", entryId: "row", name: file.name))
        XCTAssertNil(reopened.load(scope: "computer-a", sessionId: "chat-b", entryId: "row", name: file.name))
        XCTAssertTrue(reopened.names(scope: "computer-a", sessionId: "chat-b", entryId: "row").isEmpty)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path })
        let payload = try XCTUnwrap(files.first { $0.pathExtension == "document" })
        try Data("broken cache".utf8).write(to: payload)
        XCTAssertNil(reopened.load(scope: "computer-a", sessionId: "chat-a", entryId: "row", name: file.name))
    }
}

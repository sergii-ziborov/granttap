import XCTest
import CryptoKit
import TweetNacl
@testable import GrantTap

@MainActor
final class TaskFileEditTests: XCTestCase {
    private func snapshot(_ text: String = "let value = 42\n", truncated: Bool = false,
                          path: String = "Sources/App.swift") -> TaskWorkspaceSnapshot {
        TaskWorkspaceSnapshot(type: "session.workspace.result", sessionId: "file-edit-chat",
            requestId: "preview", path: path, text: text, truncated: truncated, createdAt: 1_000)
    }

    func testSubmittingEditsCreatesOneTaskRequestWithTheExactOriginalAndProposedText() throws {
        let model = AppModel()
        model.demoMode = true
        model.deliveries = []
        let chat = SessionInfo(sessionId: "file-edit-chat", agent: "codex", state: "working",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        let original = "let title = \"Привет\"\r\n", proposed = "let title = \"Hello\"\r\n"
        let id = try XCTUnwrap(model.queueTaskFileEdit(snapshot: snapshot(original), replacement: proposed, to: chat))
        XCTAssertEqual(model.deliveries.count, 1)
        let row = try XCTUnwrap(model.deliveries.first)
        XCTAssertEqual(row.id, id)
        XCTAssertEqual(row.sessionId, chat.sessionId)
        XCTAssertEqual(row.agent, "codex")
        XCTAssertNotNil(row.chatQueue)
        let attachment = try XCTUnwrap(row.attachments.first)
        XCTAssertEqual(attachment.mimeType, "application/json")
        let data = try XCTUnwrap(Data(base64Encoded: attachment.data))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(fields["originalText"] as? String, original)
        XCTAssertEqual(fields["proposedText"] as? String, proposed)
        let hash = SHA256.hash(data: Data(original.utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(fields["baseSHA256"] as? String, hash)
        XCTAssertEqual(fields["path"] as? String, "Sources/App.swift")
    }

    func testPartialUnchangedOversizedAndInvalidFilesCannotBecomeEditRequests() throws {
        XCTAssertThrowsError(try TaskFileEditRequest(snapshot: snapshot(truncated: true), replacement: "new"))
        XCTAssertThrowsError(try TaskFileEditRequest(snapshot: snapshot(), replacement: "let value = 42\n"))
        XCTAssertThrowsError(try TaskFileEditRequest(snapshot: snapshot(), replacement: String(repeating: "x", count: 131_073)))
        for path in ["", "../outside", "/outside", "dir\\outside"] {
            XCTAssertThrowsError(try TaskFileEditRequest(snapshot: snapshot(path: path), replacement: "new"))
        }
        let blank = try TaskFileEditRequest(snapshot: snapshot(), replacement: "")
        XCTAssertEqual(blank.proposedText, "", "Deleting all contents is a valid explicit proposal.")
        let normalized = try TaskFileEditRequest(snapshot: snapshot("é"), replacement: "e\u{301}")
        XCTAssertNotEqual(normalized.baseSHA256, normalized.proposedSHA256)
    }

    func testAnotherChatAndRejectedQueueDoNotCreateOrLoseAnEdit() throws {
        let model = AppModel()
        model.demoMode = true
        model.deliveries = []
        let other = SessionInfo(sessionId: "other-chat", agent: "claude", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        XCTAssertThrowsError(try model.queueTaskFileEdit(snapshot: snapshot(), replacement: "new", to: other))
        XCTAssertTrue(model.deliveries.isEmpty)
        let current = SessionInfo(sessionId: "file-edit-chat", agent: "codex", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        for index in 0..<DeliveryPersistence.maxActiveCount {
            XCTAssertTrue(model.queueChatMessage("Queued request \(index)", to: current))
        }
        let previous = Set(model.deliveries.map(\.id))
        XCTAssertNil(try model.queueTaskFileEdit(snapshot: snapshot(), replacement: "new", to: current))
        XCTAssertTrue(previous.isSubset(of: Set(model.deliveries.map(\.id))))
        for failure in [TaskFileEditRequest.Failure.incomplete, .unchanged, .tooLarge] {
            XCTAssertFalse(failure.localizedDescription.isEmpty)
        }
    }

    func testEditRequestSurvivesPersistenceAndMachineDecryptionWithoutAnOnlineComputer() throws {
        let model = AppModel()
        model.demoMode = true
        model.deliveries = []
        let chat = SessionInfo(sessionId: "file-edit-chat", agent: "codex", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        let id = try XCTUnwrap(model.queueTaskFileEdit(snapshot: snapshot(), replacement: "let value = 7\n", to: chat))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("queue.json")
        DeliveryPersistence.save(model.deliveries, to: file)
        let restored = try XCTUnwrap(DeliveryPersistence.load(from: file).first { $0.id == id })
        let phone = try NaclBox.keyPair(), machine = try NaclBox.keyPair()
        let pairing = Pairing(relayUrl: "wss://relay.test", room: String(repeating: "a", count: 32),
            role: "phone", deviceName: "Fixture", senderId: "fixture",
            myPublicKey: phone.publicKey.base64EncodedString(), mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: machine.publicKey.base64EncodedString(), pushAuth: String(repeating: "b", count: 64))
        let reservation = try RelayTaskQueueEncoding.prepare(model.wireUserMessage(for: restored), pairing: pairing,
            notBefore: floor(restored.createdAt), now: floor(restored.createdAt))
        let metadata = try RelayTaskQueueCipherStore.save(reservation, directory: directory)
        let envelope = try XCTUnwrap(RelayTaskQueueCipherStore.restore(metadata, directory: directory).envelope)
        let plain = try XCTUnwrap(Crypto.open(nonceB64: envelope.nonce, boxB64: envelope.box,
            theirPublicKeyB64: pairing.myPublicKey, mySecretKeyB64: machine.secretKey.base64EncodedString()))
        let job = try JSONDecoder().decode(RelayQueuedTask.self, from: plain)
        XCTAssertEqual(job.operation.sessionId, chat.sessionId)
        XCTAssertEqual(job.operation.attachments?.first?.data, restored.attachments.first?.data)
        XCTAssertFalse(String(data: try reservation.uploadBody(), encoding: .utf8)!.contains("let value"))
        XCTAssertFalse(model.connected)
    }

    func testDiffShowsActualLinesEmptyFilesUnicodeAndFinalNewlineChangesWithBoundedRendering() {
        let diff = TaskFileEditDiff(original: "let value = 42\n", proposed: "let value = 7\n", path: "App.swift")
        XCTAssertTrue(diff.text.contains("-let value = 42"))
        XCTAssertTrue(diff.text.contains("+let value = 7"))
        XCTAssertFalse(diff.truncated)
        XCTAssertEqual(TaskFileEditDiff(original: "same", proposed: "same", path: "file").text, "")
        XCTAssertTrue(TaskFileEditDiff(original: "", proposed: "é", path: "file").text.contains("+é"))
        XCTAssertTrue(TaskFileEditDiff(original: "old", proposed: "", path: "file").text.contains("-old"))
        let newline = TaskFileEditDiff(original: "text", proposed: "text\n", path: "file")
        XCTAssertTrue(newline.text.contains("\\ No newline at end of file"))
        XCTAssertTrue(newline.text.contains("-text"))
        XCTAssertTrue(newline.text.contains("+text"))
        let large = TaskFileEditDiff(original: String(repeating: "old\n", count: 1_000),
            proposed: String(repeating: "new\n", count: 1_000), path: "file")
        XCTAssertTrue(large.truncated)
        XCTAssertLessThanOrEqual(large.text.components(separatedBy: "\n").count, 401)
        let context = TaskFileEditDiff(original: "first\nold\nlast\n", proposed: "first\nnew\nlast\n", path: "file")
        XCTAssertTrue(context.text.contains(" first"))
        XCTAssertTrue(context.text.contains(" last"))
    }

    func testTheSameDraftSurvivesContentChangesAndAnAlreadyQueuedDraftCanClose() {
        let draft = TaskFileEditDraft(snapshot: snapshot())
        var closed = 0
        draft.requestClose { closed += 1 }
        XCTAssertEqual(closed, 1)
        draft.text = "let value = 7\n"
        XCTAssertTrue(draft.changed)
        XCTAssertEqual(draft.snapshot.text, "let value = 42\n")
        draft.deliveryId = "already-queued"
        draft.requestClose { closed += 1 }
        XCTAssertEqual(closed, 2)
        XCTAssertEqual(draft.text, "let value = 7\n")
    }

    func testModifiedFilePathsStayInsideTheExactExecutionWorkspace() {
        let chat = SessionInfo(sessionId: "file-edit-chat", agent: "codex", cwd: "/repo", state: "idle",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        XCTAssertEqual(TaskFileEditPath.relative("/repo/Sources/App.swift", session: chat), "Sources/App.swift")
        XCTAssertEqual(TaskFileEditPath.relative("Sources/App.swift", session: chat), "Sources/App.swift")
        for path in ["/repo-other/private", "../private", "", "dir\\private", "file\0name"] {
            XCTAssertNil(TaskFileEditPath.relative(path, session: chat))
        }
    }
}

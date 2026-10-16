import XCTest
import UIKit
@testable import GrantTap

@MainActor
final class QueuedImageRetentionTests: XCTestCase {
    func testTwoQueuedPicturesRemainReadableAfterNativeEchoAndOutboxRemoval() async throws {
        let model = AppModel()
        model.demoMode = true
        model.deliveries = []
        model.activities = [:]
        model.localOnlySessionIds = []
        let session = SessionInfo(sessionId: UUID().uuidString, agent: "codex", state: "working",
            startedAt: 1, lastActivityAt: 2, tokensSession: 0, tokensLastTurn: 0)
        model.sessions = [session]
        let first = picture(.red), second = picture(.blue)
        model.queueChatMessage("First photo", to: session, attachments: [first])
        model.queueChatMessage("Second photo", to: session, attachments: [second])
        let ids = model.deliveries.map(\.id)
        model.sendChatQueuedMessageNow(ids[0])
        model.sendChatQueuedMessageNow(ids[1])
        let local = try XCTUnwrap(model.activities[session.sessionId])
        XCTAssertEqual(local.entries.count, 2)
        for entry in local.entries {
            let imageId = try XCTUnwrap(entry.images?.first?.id)
            let data = try await model.messageImageData(sessionId: session.sessionId, imageId: imageId)
            XCTAssertNotNil(UIImage(data: data))
        }
        let times = local.entries.map(\.createdAt)
        let incoming = SessionActivity(type: "session.activity", sessionId: session.sessionId,
            agent: "codex", state: "working", entries: [
                ActivityEntry(id: "caption-one", kind: "user", text: "First photo", createdAt: times[0]),
                ActivityEntry(id: "picture-one", kind: "user", text: "", createdAt: times[0], attachments: ["Image"]),
                ActivityEntry(id: "caption-two", kind: "user", text: "Second photo", createdAt: times[1] + 1_000),
                ActivityEntry(id: "picture-two", kind: "user", text: "", createdAt: times[1] + 1_000, attachments: ["Image"])
            ], generatedAt: times[1] + 2_000)
        _ = model.reconcileOptimisticUserBubbles(existing: local, incoming: incoming, sourceNamespace: nil)
        model.deliveries = []
        let recoveredFirst = try await model.messageImageData(sessionId: session.sessionId, imageId: "picture-one")
        let recoveredSecond = try await model.messageImageData(sessionId: session.sessionId, imageId: "picture-two")
        XCTAssertEqual(recoveredFirst, Data(base64Encoded: first.data))
        XCTAssertEqual(recoveredSecond, Data(base64Encoded: second.data))
    }

    private func picture(_ color: UIColor) -> UserAttachment {
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return UserAttachment(name: "Photo.png", mimeType: "image/png", data: bytes.base64EncodedString())
    }
}

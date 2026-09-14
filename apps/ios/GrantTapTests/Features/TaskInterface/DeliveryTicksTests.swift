import XCTest
@testable import GrantTap

/// A message you sent should carry its own delivery mark, the way a messenger
/// does — not appear a second time as a status card underneath the chat.
final class DeliveryTicksTests: XCTestCase {
    private func delivery(id: String, state: DeliveryState) -> OutgoingDelivery {
        let now = Date().timeIntervalSince1970 * 1_000
        return OutgoingDelivery(
            id: id, text: "hello", agent: nil, cwd: nil, sessionId: "s-1",
            requestId: nil, roomId: "room-a", attachments: [],
            preferredMcp: nil, skill: nil,
            createdAt: now, updatedAt: now, attempts: 1,
            state: state, error: nil, nextRetryAt: nil
        )
    }

    func testEveryDeliveryStateHasAMark() {
        XCTAssertEqual(DeliveryTick.forState(.queued), .queued)
        XCTAssertEqual(DeliveryTick.forState(.sending), .sending)
        XCTAssertEqual(DeliveryTick.forState(.delivered), .delivered)
        XCTAssertEqual(DeliveryTick.forState(.failed), .failed)
    }

    func testOnlyAFailureIsColoured() {
        XCTAssertTrue(DeliveryTick.failed.isAlarming)
        for tick in [DeliveryTick.queued, .sending, .delivered] {
            XCTAssertFalse(tick.isAlarming, "a normal send must not shout")
        }
    }

    func testConfirmedAndMerelySentLookDifferent() {
        XCTAssertNotEqual(
            DeliveryTick.sending.systemImage,
            DeliveryTick.delivered.systemImage,
            "left the phone and reached the computer are not the same thing"
        )
    }

    func testEachMarkSaysWhatItMeansOutLoud() {
        XCTAssertEqual(DeliveryTick.queued.accessibilityLabel, "Queued")
        XCTAssertEqual(DeliveryTick.delivered.accessibilityLabel, "Delivered")
        XCTAssertEqual(DeliveryTick.failed.accessibilityLabel, "Not delivered")
    }

    @MainActor
    func testTheBubbleFindsItsOwnDelivery() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        _ = now
        model.deliveries = [delivery(id: "d-1", state: .sending)]

        XCTAssertEqual(model.deliveryTick(forEntryId: "local-user-d-1"), .sending)
        XCTAssertNil(
            model.deliveryTick(forEntryId: "provider-row-9"),
            "a line from the transcript is not something the phone is still sending"
        )
    }

    @MainActor
    func testADeliveredMessageStopsBeingTracked() {
        let model = AppModel()
        let now = Date().timeIntervalSince1970 * 1_000
        _ = now
        model.deliveries = [delivery(id: "d-2", state: .delivered)]
        XCTAssertEqual(model.deliveryTick(forEntryId: "local-user-d-2"), .delivered)
    }

    @MainActor
    func testChatCapturePhotoCanBeOpenedFromItsOwnBubble() {
        let capture = AppModelDemoFixtures.chatCapture(at: 10_000)
        let model = AppModel()
        model.deliveries = [capture.delivery]

        let photoEntry = capture.activity.entries.first { entry in
            entry.id.hasPrefix("local-user-") && entry.attachments == ["release-check.jpg"]
        }
        XCTAssertNotNil(photoEntry)
        XCTAssertNotNil(
            photoEntry.flatMap {
                model.sentAttachmentImage(forEntryId: $0.id, name: "release-check.jpg")
            },
            "the deterministic local photo must exercise the real full-screen preview path"
        )
    }

    func testChatCaptureContainsOneShortAgentReply() {
        let capture = AppModelDemoFixtures.chatCapture(at: 10_000)
        let replies = capture.activity.entries.filter {
            ($0.kind == "message" || $0.kind == "final") && $0.text == "ok"
        }

        XCTAssertEqual(replies.count, 1, "the capture must not reintroduce the stuck duplicate")
    }
}

import XCTest
@testable import GrantTap

final class ChatSurfaceOcclusionTests: XCTestCase {
    func testBottomReplyDoesNotCoverTheLastConversationRow() {
        let conversation = CGRect(x: 0, y: 90, width: 700, height: 810)
        let reply = CGRect(x: 0, y: 780, width: 700, height: 120)
        XCTAssertEqual(ChatSurfaceOcclusion.bottomInset(conversation: conversation, reply: reply), 120)
    }

    func testSeparateBookAndLaptopPanesDoNotLoseReadingSpace() {
        let conversation = CGRect(x: 0, y: 90, width: 700, height: 360)
        for reply in [CGRect(x: 0, y: 465, width: 700, height: 120),
                      CGRect(x: 720, y: 90, width: 350, height: 360)] {
            XCTAssertEqual(ChatSurfaceOcclusion.bottomInset(conversation: conversation, reply: reply), 0)
        }
    }

    func testOffscreenAndInvalidReplyFramesNeverMoveTheConversation() {
        let conversation = CGRect(x: 0, y: 90, width: 700, height: 810)
        for reply in [CGRect.null, CGRect.zero, CGRect(x: 0, y: 930, width: 700, height: 80)] {
            XCTAssertEqual(ChatSurfaceOcclusion.bottomInset(conversation: conversation, reply: reply), 0)
        }
    }

    func testInsetIsClampedToTheVisibleConversation() {
        let conversation = CGRect(x: 20, y: 100, width: 650, height: 240)
        XCTAssertEqual(ChatSurfaceOcclusion.bottomInset(conversation: conversation,
            reply: CGRect(x: 0, y: 0, width: 700, height: 600)), 240)
    }

    func testSideAndFloatingSurfacesDoNotShortenEveryMessageRow() {
        let conversation = CGRect(x: 0, y: 0, width: 700, height: 800)
        for reply in [CGRect(x: 500, y: 0, width: 200, height: 800),
                      CGRect(x: 0, y: 100, width: 700, height: 120)] {
            XCTAssertEqual(ChatSurfaceOcclusion.bottomInset(conversation: conversation, reply: reply), 0)
        }
    }

    func testInvalidConversationAndUnboundedFramesCannotProduceInfiniteInsets() {
        let reply = CGRect(x: 0, y: 200, width: 700, height: 100)
        for conversation in [CGRect.zero, CGRect.null, CGRect.infinite] {
            XCTAssertEqual(ChatSurfaceOcclusion.bottomInset(conversation: conversation, reply: reply), 0)
        }
        XCTAssertEqual(ChatSurfaceOcclusion.bottomInset(conversation: reply, reply: .infinite), 0)
    }
}

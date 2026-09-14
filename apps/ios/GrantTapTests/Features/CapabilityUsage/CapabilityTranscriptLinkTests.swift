import XCTest
@testable import GrantTap

/// Tapping a call in history must land on that call, so the entry it came from
/// has to be recoverable from what the usage row stored.
final class CapabilityTranscriptLinkTests: XCTestCase {
    func testTheRoomPrefixIsStrippedFromAStoredSourceId() {
        XCTAssertEqual(
            CapabilityTranscriptLink.entryId(sourceId: "room-a:entry-7", roomId: "room-a"),
            "entry-7"
        )
        // A row that was never namespaced is already the entry id.
        XCTAssertEqual(
            CapabilityTranscriptLink.entryId(sourceId: "entry-7", roomId: "room-a"), "entry-7"
        )
        // Another room's prefix is not this room's, so nothing is stripped.
        XCTAssertEqual(
            CapabilityTranscriptLink.entryId(sourceId: "room-b:entry-7", roomId: "room-a"),
            "room-b:entry-7"
        )
    }

    func testALegacyMultiCapabilityRowPointsAtItsOwnEntry() {
        // One call that observed several capabilities stored one row per
        // observation, suffixed with its index. All of them are the same entry.
        XCTAssertEqual(
            CapabilityTranscriptLink.entryId(
                sourceId: "room-a:entry-7:capability:2", roomId: "room-a"
            ), "entry-7"
        )
        XCTAssertEqual(
            CapabilityTranscriptLink.entryId(
                sourceId: "room-a:entry-7:capability:0", roomId: "room-a"
            ), "entry-7"
        )
    }

    func testAnEntryIdSurvivesColonsOfItsOwn() {
        // Provider ids contain colons; only the room prefix and the capability
        // suffix may be removed.
        XCTAssertEqual(
            CapabilityTranscriptLink.entryId(
                sourceId: "room-a:tool:call:99:capability:1", roomId: "room-a"
            ), "tool:call:99"
        )
    }

    func testNothingUsableReportsNothing() {
        XCTAssertNil(CapabilityTranscriptLink.entryId(sourceId: "", roomId: "room-a"))
        XCTAssertNil(CapabilityTranscriptLink.entryId(sourceId: "room-a:", roomId: "room-a"))
        XCTAssertNil(CapabilityTranscriptLink.entryId(sourceId: "   ", roomId: nil))
        XCTAssertEqual(
            CapabilityTranscriptLink.entryId(sourceId: "entry-1", roomId: nil), "entry-1"
        )
    }
}

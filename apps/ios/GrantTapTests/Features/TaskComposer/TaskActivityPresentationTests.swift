import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class TaskActivityPresentationTests: XCTestCase {
    func testStopKeepsWorkingPausingAndDisconnectedStatesDistinctWithReducedMotion() {
        RenderProbe.render(VStack {
            TaskComposerStopButton(pending: false, active: true, stop: {})
            TaskComposerStopButton(pending: true, active: true, stop: {})
            TaskComposerStopButton(pending: false, active: false, stop: {})
        })
        let first = Date(timeIntervalSinceReferenceDate: 0.1)
        let next = first.addingTimeInterval(0.5)
        XCTAssertEqual(TaskWorkingRing.rotation(at: first, reduceMotion: true),
                       TaskWorkingRing.rotation(at: next, reduceMotion: true))
        XCTAssertNotEqual(TaskWorkingRing.rotation(at: first, reduceMotion: false),
                          TaskWorkingRing.rotation(at: next, reduceMotion: false))
    }
}

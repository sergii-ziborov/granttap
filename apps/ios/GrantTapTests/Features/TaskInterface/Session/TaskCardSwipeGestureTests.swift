import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class TaskCardSwipeGestureTests: XCTestCase {
    private final class Pan: UIPanGestureRecognizer {
        var speed = CGPoint.zero
        override func velocity(in view: UIView?) -> CGPoint { speed }
    }

    func testVerticalAndDiagonalScrollsAreRejectedBeforeTheCardRecognizesThem() {
        let view = TaskCardSwipeView(frame: .init(x: 0, y: 0, width: 300, height: 100))
        let pan = Pan()
        for point in [CGPoint(x: 0, y: 500), .init(x: 200, y: 500), .init(x: 400, y: 400), .zero] {
            pan.speed = point
            XCTAssertFalse(view.gestureRecognizerShouldBegin(pan))
        }
        for x in [-500.0, 500.0] {
            pan.speed = CGPoint(x: x, y: 100)
            XCTAssertTrue(view.gestureRecognizerShouldBegin(pan))
        }
        XCTAssertFalse(view.gestureRecognizerShouldBegin(UITapGestureRecognizer()))
        pan.speed = .init(x: CGFloat.nan, y: 1)
        XCTAssertFalse(view.gestureRecognizerShouldBegin(pan))
        XCTAssertTrue(view.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: UIPanGestureRecognizer()))
        view.detach()
    }
}

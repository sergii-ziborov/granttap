import XCTest
@testable import GrantTap

final class ProjectArchitectureViewportTests: XCTestCase {
    func testPortraitAndLandscapeFitEveryComponentIncludingLabelSpace() {
        let points: [SIMD3<Float>] = [SIMD3(-14, -4, -2), SIMD3(14, 4, 2), SIMD3(0, 12, 6)]
        let portrait = CGSize(width: 300, height: 600)
        let landscape = CGSize(width: 600, height: 300)
        let portraitFrame = ProjectArchitectureViewport.frame(points: points, size: portrait)
        let landscapeFrame = ProjectArchitectureViewport.frame(points: points, size: landscape)
        XCTAssertLessThan(landscapeFrame.distance, portraitFrame.distance)
        for size in [portrait, landscape, CGSize(width: 1_024, height: 768)] {
            let frame = ProjectArchitectureViewport.frame(points: points, size: size)
            let tangent = tan(Float(57) * .pi / 360)
            for point in points {
                let delta = point - frame.center
                let depth = frame.distance - delta.z
                XCTAssertLessThan(abs(delta.x) + 3.2, depth * tangent * Float(size.width / size.height))
                XCTAssertLessThan(abs(delta.y) + 2.5, depth * tangent)
            }
        }
        let reversed = ProjectArchitectureViewport.frame(points: Array(points.reversed()), size: portrait)
        XCTAssertEqual(portraitFrame.distance, reversed.distance)
        XCTAssertEqual(portraitFrame.center, reversed.center)
    }

    func testEmptyInvalidAndNotYetLaidOutViewportsRemainFinite() {
        let empty = ProjectArchitectureViewport.frame(points: [], size: .zero)
        XCTAssertEqual(empty.center, .zero)
        XCTAssertEqual(empty.distance, 12)
        let invalid = ProjectArchitectureViewport.frame(points: [SIMD3(.nan, 0, 0)], size: .zero)
        XCTAssertEqual(invalid.distance, 12)
        let single = ProjectArchitectureViewport.frame(points: [SIMD3(8, 2, -1)], size: .zero)
        XCTAssertEqual(single.center, SIMD3(8, 2, -1))
        XCTAssertTrue(single.distance.isFinite)
        XCTAssertGreaterThanOrEqual(single.distance, 10)
    }
}

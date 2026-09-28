import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class ChatFileReviewTests: XCTestCase {
    func testCombinedEditsKeepTheIncompletePreviewEvidence() {
        let cut = RecordedFileChange(path: "/demo/file.sh", linesAdded: 2, linesRemoved: 1,
            diff: "+first", diffTruncated: true)
        let next = RecordedFileChange(path: cut.path, linesAdded: 1, linesRemoved: 0, diff: "+next")
        let complete = RecordedFileChange(path: "/demo/other.sh", linesAdded: 1, linesRemoved: 0, diff: "+whole")
        let entries = [ActivityEntry(id: "user", kind: "user", text: "Edit", createdAt: 1),
            ActivityEntry(id: "first", kind: "tool", text: "Saved", createdAt: 2, fileChanges: [cut]),
            ActivityEntry(id: "next", kind: "tool", text: "Saved", createdAt: 3, fileChanges: [next, complete]),
            ActivityEntry(id: "final", kind: "final", text: "Done", createdAt: 4)]
        let files = ChatFileChanges.endingAt("final", entries: entries)
        XCTAssertEqual(files.first?.diffTruncated, true)
        XCTAssertEqual(files.first?.diff, "+first\n+next")
        XCTAssertNil(files.last?.diffTruncated)
    }

    func testLongDiffKeepsUnwrappedLinesAndStartsAtTheLeadingEdge() throws {
        let text = "+START " + String(repeating: "readable source ", count: 40) + " END\n+short line"
        let file = RecordedFileChange(path: "/demo/long-file.sh", linesAdded: 2, linesRemoved: 0, diff: text)
        let controller = UIHostingController(rootView: ChatFileReviewSheet(file: file, onClose: {}))
        let frame = CGRect(x: 0, y: 0, width: 560, height: 600)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let scroll = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIScrollView }
            .max { $0.contentSize.width < $1.contentSize.width })
        XCTAssertGreaterThan(scroll.contentSize.width, scroll.bounds.width * 2,
            "The entire unwrapped line must be horizontally reachable.")
        XCTAssertLessThan(scroll.contentSize.height, 150, "A long code line must not wrap vertically.")
        XCTAssertEqual(scroll.contentOffset.x, -scroll.adjustedContentInset.left, accuracy: 1)
        let screenshot = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "Review leading edge"
        attachment.lifetime = .keepAlways
        add(attachment)
        scroll.setContentOffset(CGPoint(x: scroll.contentSize.width - scroll.bounds.width, y: 0), animated: false)
        XCTAssertGreaterThan(scroll.contentOffset.x, 1000)
        #if targetEnvironment(macCatalyst)
        let bars = descendants(controller.view).compactMap { $0 as? UINavigationBar }
        XCTAssertTrue(bars.allSatisfy { $0.isHidden || $0.alpha == 0 })
        #endif
    }

    func testDiffStartsAtTheTopEvenWhenItHasOnlyTwoLines() throws {
        var bounds = CGRect.null
        let view = ChatFileDiffViewport {
            Rectangle().frame(width: 2000, height: 36)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: ReviewContentBounds.self,
                        value: geometry.frame(in: .named("viewport")))
                })
        }.coordinateSpace(name: "viewport")
            .onPreferenceChange(ReviewContentBounds.self) { bounds = $0 }
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 560, height: 600))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertFalse(bounds.isNull)
        XCTAssertEqual(bounds.minX, 16, accuracy: 1)
        XCTAssertEqual(bounds.minY, 16, accuracy: 1,
            "Short diffs must start at the top instead of floating in the middle.")
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

private struct ReviewContentBounds: PreferenceKey {
    static var defaultValue: CGRect { .null }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

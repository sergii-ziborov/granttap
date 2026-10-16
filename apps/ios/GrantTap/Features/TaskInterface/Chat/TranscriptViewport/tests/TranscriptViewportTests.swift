import XCTest
import SwiftUI
@testable import GrantTap

@MainActor
final class TranscriptViewportTests: XCTestCase {
    func testLongTranscriptBuildsOnlyViewportRowsAndCanReachBothEnds() {
        let visits = RowVisits()
        let rows = 5_000
        let view = ScrollViewReader { proxy in
            ChatTranscriptViewport {
                ForEach(0..<rows, id: \.self) { index in
                    CountedTranscriptRow(index: index, visits: visits).id(index)
                }
            }
            .onAppear { proxy.scrollTo(rows - 1, anchor: .bottom) }
        }
        let controller = UIHostingController(rootView: view)
        let frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        defer { window.isHidden = true }
        XCTAssertTrue(visits.ids.contains(rows - 1), "The latest saved message must be reachable.")
        XCTAssertLessThan(visits.ids.count, 100, "Old history must not all be rendered at once.")
        print("TRANSCRIPT_RENDER_WITNESS rows=\(rows) rendered=\(visits.ids.count)")
    }
}

private final class RowVisits {
    var ids = Set<Int>()
}

private struct CountedTranscriptRow: View {
    let index: Int
    let visits: RowVisits
    var body: some View {
        let _ = visits.ids.insert(index)
        Text("Saved message \(index)").frame(height: 80)
    }
}

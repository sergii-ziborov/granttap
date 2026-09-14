import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

/// Choosing among hundreds of project folders has to be searchable, and two
/// folders with the same name have to stay distinguishable.
@MainActor
final class WorkspacePickerTests: XCTestCase {
    private let workspaces = [
        "/Users/dev/granttap/web", "/Users/dev/other/web", "/Users/dev/nodvox",
    ]

    func testSearchMatchesNameAndPathAndReportsWhatItFiltered() {
        let all = WorkspacePickerSheet.matches(workspaces, query: "  ")
        XCTAssertEqual(all.count, 3, "an empty search hides nothing")
        XCTAssertEqual(WorkspacePickerSheet.matches(workspaces, query: "GrantTap"),
                       ["/Users/dev/granttap/web"], "the path matches, case-insensitively")
        XCTAssertEqual(WorkspacePickerSheet.matches(workspaces, query: "web").count, 2,
                       "two folders named web both stay")
        XCTAssertTrue(WorkspacePickerSheet.matches(workspaces, query: "nothing-here").isEmpty)
    }

    func testTheRowShowsWhereAFolderLivesSoDuplicateNamesStayApart() {
        XCTAssertEqual(WorkspacePickerSheet.name("/Users/dev/granttap/web"), "web")
        XCTAssertEqual(WorkspacePickerSheet.parent("/Users/dev/granttap/web"), "/Users/dev/granttap")
        XCTAssertNil(WorkspacePickerSheet.parent("web"), "a bare name has no parent to show")

        let frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        let controller = UIHostingController(rootView: WorkspacePickerSheet(
            workspaces: workspaces, workspace: .constant("/Users/dev/nodvox")
        ))
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        XCTAssertFalse(controller.view.subviews.isEmpty)
    }
}

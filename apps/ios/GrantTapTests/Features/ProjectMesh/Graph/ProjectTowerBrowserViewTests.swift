import XCTest
import SwiftUI
@testable import GrantTap

@MainActor
final class ProjectTowerBrowserViewTests: XCTestCase {
    func testReceivedBrowserPreservesPartialScopeAndExactAvailableFilePaths() throws {
        let map = try ProjectTowerViewFixtures.received(ProjectTowerViewFixtures.map(partial: true))
        let subject = ProjectTowerBrowser(map: map) { _, _ in
            XCTFail("Opening the browser must not navigate before a file is chosen")
        }
        XCTAssertTrue(ProjectTowerViewProbe.render(subject).attachedToWindow)
        let groups = ProjectTowerInspection.browserGroups(map: subject.map, query: "")
        XCTAssertEqual(groups.flatMap(\.files).map(\.file.path).sorted(),
                       ["README.md", ProjectTowerViewFixtures.path].sorted())
        XCTAssertTrue(groups.flatMap(\.files).allSatisfy { $0.symbols.isEmpty })
        XCTAssertEqual(subject.map.files.count, 2)
        XCTAssertEqual(subject.map.totalFiles, 9)
        XCTAssertTrue(subject.map.truncated)
    }

    func testEnteredSearchResolvesTheLastSymbolToItsExactSourceFile() throws {
        let map = try ProjectTowerViewFixtures.received(ProjectTowerViewFixtures.map())
        let subject = ProjectTowerBrowser(map: map) { _, _ in
            XCTFail("Typing a query must not choose a result automatically")
        }
        let mounted = ProjectTowerViewProbe.render(subject, query: "section36")
        XCTAssertTrue(mounted.attachedToWindow)
        XCTAssertEqual(mounted.editorText, "section36")
        let matches = ProjectTowerInspection.browserGroups(map: subject.map, query: mounted.editorText!)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.files.count, 1)
        XCTAssertEqual(matches.first?.files.first?.file.path, ProjectTowerViewFixtures.path)
        XCTAssertEqual(matches.first?.files.first?.symbols.map(\.id), ["section-36"])
        XCTAssertEqual(matches.first?.files.first?.symbols.first?.startLine, 360)
    }

    func testUnknownSearchHasNoSelectableSourceFactsAndDoesNotNavigate() {
        let map = ProjectTowerViewFixtures.map()
        let subject = ProjectTowerBrowser(map: map) { _, _ in
            XCTFail("A query without matches must not navigate")
        }
        let mounted = ProjectTowerViewProbe.render(subject, query: "does-not-exist")
        XCTAssertTrue(mounted.attachedToWindow)
        XCTAssertEqual(mounted.editorText, "does-not-exist")
        XCTAssertTrue(ProjectTowerInspection.browserGroups(map: subject.map, query: mounted.editorText!).isEmpty)
        XCTAssertEqual(subject.map, map)
        let empty = ProjectCodeMap(files: [], roads: [], totalFiles: 0, truncated: false)
        XCTAssertTrue(ProjectTowerViewProbe.render(ProjectTowerBrowser(map: empty) { _, _ in
            XCTFail("An empty received map must not navigate")
        }).attachedToWindow)
    }
}

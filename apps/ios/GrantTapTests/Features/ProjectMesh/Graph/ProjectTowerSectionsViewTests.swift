import XCTest
import SwiftUI
@testable import GrantTap

@MainActor
final class ProjectTowerSectionsViewTests: XCTestCase {
    func testEmptySectionsMountWithoutInventingASourceEntryOrChangingSelection() {
        let sections = ProjectTowerInspection.sections(path: "README.md", map: ProjectTowerViewFixtures.map())
        let subject = ProjectTowerSectionsView(sections: sections, selectedSymbol: nil, colors: [:], onSelect: { _ in
            XCTFail("Mounting an empty source list must not select a section")
        })
        XCTAssertTrue(ProjectTowerViewProbe.render(subject).attachedToWindow)
        XCTAssertTrue(subject.sections.isEmpty)
        XCTAssertNil(subject.selectedSymbol)
    }

    func testSelectedLastSectionKeepsExactLocationAndSelectionAcrossTheMountedView() {
        let sections = ProjectTowerInspection.sections(path: ProjectTowerViewFixtures.path,
                                                      map: ProjectTowerViewFixtures.map())
        let subject = ProjectTowerSectionsView(sections: sections, selectedSymbol: "section-36",
            colors: ["section-36": .cyan], onSelect: { _ in
                XCTFail("Rendering a selected section must not send another selection")
            })
        XCTAssertTrue(ProjectTowerViewProbe.render(subject, height: 3_600).attachedToWindow)
        let selected = subject.sections.first { $0.symbol.id == subject.selectedSymbol }
        XCTAssertEqual(selected?.path, ProjectTowerViewFixtures.path)
        XCTAssertEqual(selected?.symbol.startLine, 360)
        XCTAssertEqual(selected?.symbol.lineCount, 36)
        XCTAssertEqual(subject.selectedSymbol, "section-36")
        XCTAssertNotNil(subject.colors["section-36"])
    }

    func testManySectionsKeepAllReportedIdentitiesIncludingAfterFiveAndTwenty() {
        let sections = ProjectTowerInspection.sections(path: ProjectTowerViewFixtures.path,
                                                      map: ProjectTowerViewFixtures.map())
        let subject = ProjectTowerSectionsView(sections: sections, selectedSymbol: nil,
                                              colors: [:], onSelect: { _ in })
        let mounted = ProjectTowerViewProbe.render(subject, height: 3_600)
        XCTAssertTrue(mounted.attachedToWindow)
        XCTAssertEqual(mounted.size.height, 3_600)
        XCTAssertEqual(subject.sections.count, 36)
        XCTAssertEqual(Set(subject.sections.map(\.id)).count, 36)
        XCTAssertEqual(subject.sections[5].symbol.id, "section-6")
        XCTAssertEqual(subject.sections[20].symbol.id, "section-21")
        XCTAssertEqual(subject.sections.last?.symbol.id, "section-36")
    }

    func testExternalLinksKeepTheirActualDirectionTypeAndDestinationInAPartialReceipt() throws {
        let map = try ProjectTowerViewFixtures.received(ProjectTowerViewFixtures.map(partial: true))
        let subject = ProjectTowerLinksView(path: ProjectTowerViewFixtures.path, map: map, roads: map.roads,
                                           onSelect: { _ in XCTFail("Rendering links must not navigate") })
        XCTAssertTrue(ProjectTowerViewProbe.render(ScrollView { subject }).attachedToWindow)
        let links = ProjectTowerInspection.links(path: subject.path, roads: subject.roads)
        let external = links.first { $0.target == ProjectTowerViewFixtures.externalId }
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(external?.source, ProjectTowerViewFixtures.path)
        XCTAssertEqual(external?.relation, "consumes")
        XCTAssertEqual(ProjectTowerInspection.displayName(path: external!.target, map: map), "Storage")
        XCTAssertEqual(links.filter { $0.target == subject.path }.map(\.source), ["README.md"])
        XCTAssertTrue(subject.map.truncated)
    }

    func testUnknownExternalDoesNotCreateALinkOrMapFileDuringMount() {
        let map = ProjectTowerViewFixtures.map()
        let subject = ProjectTowerLinksView(path: "ext:unknown", map: map, roads: map.roads,
                                           onSelect: { _ in XCTFail("An unknown item must not navigate") })
        XCTAssertTrue(ProjectTowerViewProbe.render(subject).attachedToWindow)
        XCTAssertEqual(ProjectTowerInspection.links(path: subject.path, roads: subject.roads), [])
        XCTAssertFalse(subject.map.files.contains { $0.path == subject.path })
        XCTAssertFalse(subject.map.externals!.contains { $0.id == subject.path })
        XCTAssertEqual(subject.map, map)
    }
}

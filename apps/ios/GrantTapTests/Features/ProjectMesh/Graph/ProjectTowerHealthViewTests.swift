import XCTest
import SwiftUI
@testable import GrantTap

@MainActor
final class ProjectTowerHealthViewTests: XCTestCase {
    func testCompleteReportKeepsMeasuredSourceAndGitRevisionSeparateFromFingerprint() throws {
        let map = try ProjectTowerViewFixtures.received(ProjectTowerViewFixtures.map())
        let report = try ProjectTowerViewFixtures.received(ProjectTowerViewFixtures.report())
        let subject = ProjectTowerHealthView(report: report, map: map,
                                            path: ProjectTowerViewFixtures.path, roads: map.roads)
        let mounted = ProjectTowerViewProbe.render(ScrollView { subject })
        XCTAssertTrue(mounted.attachedToWindow)
        XCTAssertEqual(mounted.size.width, 430)
        XCTAssertTrue(subject.map.valid())
        XCTAssertEqual(subject.map.files.first?.lineCount, 410)
        XCTAssertEqual(subject.report.analysisStatus, "COMPLETE")
        XCTAssertEqual(subject.report.sourceRevision, "git-fixture-head")
        XCTAssertEqual(subject.report.revision, "content-fingerprint")
        XCTAssertNotEqual(subject.report.sourceRevision, subject.report.revision)
        XCTAssertFalse(subject.report.truncated)
    }

    func testPartialReceiptPreservesUnknownLOCAndItsDiagnosticWithoutCreatingSourceEvidence() throws {
        let map = try ProjectTowerViewFixtures.received(ProjectTowerViewFixtures.map(partial: true, measuredLOC: nil))
        let report = try ProjectTowerViewFixtures.received(ProjectTowerViewFixtures.report(status: "INCOMPLETE", partial: true))
        let subject = ProjectTowerHealthView(report: report, map: map,
                                            path: ProjectTowerViewFixtures.path, roads: [])
        XCTAssertTrue(ProjectTowerViewProbe.render(ScrollView { subject }).attachedToWindow)
        XCTAssertTrue(subject.map.valid())
        XCTAssertNil(subject.map.files.first?.lineCount)
        XCTAssertTrue(subject.report.truncated)
        XCTAssertTrue(subject.map.truncated)
        XCTAssertEqual(subject.report.analysisErrorCode, "incomplete_sources")
        XCTAssertEqual(subject.report.analysisStatus, "INCOMPLETE")
        XCTAssertEqual(ProjectTowerInspection.links(path: subject.path, roads: subject.roads), [])
        XCTAssertEqual(subject.map.totalFiles, 9)
        XCTAssertEqual(subject.map.files.count, 2)
    }

    func testExternalAndLegacyReceiptKeepsRevisionUnknownAndCountsOnlyObservedLinks() throws {
        let map = try ProjectTowerViewFixtures.received(ProjectTowerViewFixtures.map())
        let report = try ProjectTowerViewFixtures.received(ProjectTowerViewFixtures.report(status: nil))
        let subject = ProjectTowerHealthView(report: report, map: map,
                                            path: ProjectTowerViewFixtures.externalId, roads: map.roads)
        XCTAssertTrue(ProjectTowerViewProbe.render(ScrollView { subject }).attachedToWindow)
        XCTAssertNil(subject.report.sourceRevision)
        XCTAssertNil(subject.report.analysisStatus)
        XCTAssertFalse(subject.map.files.contains { $0.path == subject.path })
        let links = ProjectTowerInspection.links(path: subject.path, roads: subject.roads)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.target, ProjectTowerViewFixtures.externalId)
        XCTAssertEqual(links.first?.relation, "consumes")
        XCTAssertEqual(subject.report.revision, "content-fingerprint")
    }

    func testSectionDetailsRetainTheSelectedReceiptWhenAnotherRevisionArrives() throws {
        var report = try ProjectTowerViewFixtures.received(ProjectTowerViewFixtures.report())
        let section = ProjectTowerInspection.sections(path: ProjectTowerViewFixtures.path,
            map: ProjectTowerViewFixtures.map()).last!
        let subject = ProjectTowerSectionDetails(report: report, section: section, partialMap: true)
        report.sourceRevision = "next-git-head"
        report.analysisId = "next-analysis"
        XCTAssertTrue(ProjectTowerViewProbe.render(subject).attachedToWindow)
        XCTAssertEqual(subject.section.path, ProjectTowerViewFixtures.path)
        XCTAssertEqual(subject.section.symbol.id, "section-36")
        XCTAssertEqual(subject.section.symbol.startLine, 360)
        XCTAssertEqual(subject.section.symbol.lineCount, 36)
        XCTAssertEqual(subject.report.sourceRevision, "git-fixture-head")
        XCTAssertEqual(subject.report.analysisId, "fixture-analysis")
        XCTAssertTrue(subject.partialMap)
        XCTAssertNotEqual(subject.report.sourceRevision, report.sourceRevision)
    }
}

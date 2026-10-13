import XCTest
@testable import GrantTap

final class ProjectTowerInspectionTests: XCTestCase {
    private func map() -> ProjectCodeMap {
        let symbols = (1...36).map { index in
            ProjectCodeMap.Symbol(id: "section-\(index)", label: "section\(index)",
                kind: "method", startLine: index * 10, lineCount: index)
        }
        return ProjectCodeMap(files: [
            .init(path: "Sources/Example.swift", language: "swift", lineCount: 410, symbols: symbols),
            .init(path: "README.md", language: "markdown", lineCount: nil, symbols: []),
            .init(path: "server/api.ts", language: "typescript", lineCount: 20, symbols: [
                .init(id: "endpoint-1", label: "GET /health", kind: "endpoint", startLine: 4, lineCount: 8)
            ])
        ], roads: [], totalFiles: 9, truncated: true)
    }

    func testEveryReportedSectionKeepsItsExactSourceLocationIncludingTheLast() {
        let sections = ProjectTowerInspection.sections(path: "Sources/Example.swift", map: map())
        XCTAssertEqual(sections.count, 36)
        XCTAssertEqual(sections.last?.symbol.id, "section-36")
        XCTAssertEqual(sections.last?.path, "Sources/Example.swift")
        XCTAssertEqual(sections.last?.symbol.startLine, 360)
        XCTAssertEqual(sections.last?.symbol.lineCount, 36)
        XCTAssertTrue(ProjectTowerInspection.sections(path: "README.md", map: map()).isEmpty)
        let endpoint = ProjectTowerInspection.sections(path: "ext:rest-api", map: map()).first
        XCTAssertEqual(endpoint?.path, "server/api.ts")
        XCTAssertEqual(endpoint?.symbol.label, "GET /health")
    }

    func testBrowserFindsSymbolsBeyondFiveAndTwentyWithoutCreatingMissingSourceFiles() {
        let matches = ProjectTowerInspection.browserGroups(map: map(), query: "  section36 ")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.files.first?.file.path, "Sources/Example.swift")
        XCTAssertEqual(matches.first?.files.first?.symbols.map(\.id), ["section-36"])
        let allSymbols = ProjectTowerInspection.browserGroups(map: map(), query: "section")
        XCTAssertEqual(allSymbols.first?.files.first?.symbols.count, 36)
        let allFiles = ProjectTowerInspection.browserGroups(map: map(), query: "")
        XCTAssertEqual(allFiles.flatMap(\.files).count, 3)
        XCTAssertTrue(allFiles.flatMap(\.files).allSatisfy { $0.symbols.isEmpty })
        XCTAssertTrue(ProjectTowerInspection.browserGroups(map: map(), query: "missing").isEmpty)
        XCTAssertNil(allFiles.flatMap(\.files).first { $0.id == "README.md" }?.file.lineCount)
    }

    func testObservedLinksDeduplicateEvidenceAndKeepDirectionAndRelationTypes() {
        let inbound = ProjectCodeMap.Road(source: "server/api.ts", target: "Sources/Example.swift", relation: "calls")
        let outbound = ProjectCodeMap.Road(source: "Sources/Example.swift", target: "ext:storage", relation: "imports")
        let unrelated = ProjectCodeMap.Road(source: "README.md", target: "server/api.ts", relation: "documents")
        let links = ProjectTowerInspection.links(path: "Sources/Example.swift",
                                                roads: [inbound, outbound, inbound, unrelated])
        XCTAssertEqual(Set(links), Set([inbound, outbound]))
        XCTAssertEqual(links.filter { $0.target == "Sources/Example.swift" }.count, 1)
        XCTAssertEqual(links.filter { $0.source == "Sources/Example.swift" }.count, 1)
        XCTAssertTrue(ProjectTowerInspection.links(path: "unknown", roads: [inbound]).isEmpty)
    }
}

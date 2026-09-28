import XCTest
@testable import GrantTap

@MainActor
final class ProjectArchitectureSceneTests: XCTestCase {
    func testFullSceneRetainsEveryReportedComponentBeyondOldPreviewLimit() {
        let nodes = (0..<64).map { index in
            ProjectRepositoryGraph.Node(id: "node-\(index)", kind: "component", label: "src/\(index)")
        }
        let relations = (1..<64).map { index in
            ProjectRepositoryGraph.Relation(source: "node-0", target: "node-\(index)",
                                            relation: "imports", evidenceCount: 1)
        }
        let report = ProjectRepositoryGraph(
            projectId: "p", repositoryId: "repo", revision: "sha", weavatrixVersion: "2.17.4",
            analysisStatus: "COMPLETE", nodes: nodes, relations: relations,
            totalNodes: nodes.count, totalRelations: relations.count, truncated: false
        )
        let positions = ProjectArchitectureScene.positions(for: report)
        XCTAssertEqual(positions.count, 64)
        XCTAssertTrue(relations.allSatisfy { positions[$0.source] != nil && positions[$0.target] != nil })
        XCTAssertTrue(positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        XCTAssertGreaterThan(Set(positions.values.map { Int(($0.z * 100).rounded()) }).count, 8,
                             "the full graph has depth rather than a flat spiral")
        let reversed = ProjectRepositoryGraph(
            projectId: report.projectId, repositoryId: report.repositoryId,
            revision: report.revision, weavatrixVersion: report.weavatrixVersion,
            nodes: Array(nodes.reversed()), relations: Array(relations.reversed()),
            totalNodes: nodes.count, totalRelations: relations.count, truncated: false
        )
        let reordered = ProjectArchitectureScene.positions(for: reversed)
        for (id, point) in positions {
            guard let other = reordered[id] else { XCTFail("Missing \(id)"); continue }
            XCTAssertEqual(point.x, other.x, accuracy: 0.001)
            XCTAssertEqual(point.y, other.y, accuracy: 0.001)
            XCTAssertEqual(point.z, other.z, accuracy: 0.001)
        }
        RenderProbe.render(ProjectArchitectureFullScreen(report: report, repositoryName: "repo"))
    }

    func testMeasuredCodeTowersKeepModuleAndSourceEvidenceInFullScreen() throws {
        let map = ProjectCodeMap(
            files: [
                .init(path: "src/domain/Store.swift", language: "swift", lineCount: 240,
                      symbols: [.init(id: "store", label: "Store", kind: "struct",
                                      startLine: 12, lineCount: 140)]),
                .init(path: "src/app/Main.swift", language: "swift", lineCount: 24,
                      symbols: [.init(id: "main", label: "main", kind: "function",
                                      startLine: 3, lineCount: 14)]),
                .init(path: "README.md", language: "markdown", lineCount: nil, symbols: []),
            ],
            roads: [.init(source: "src/app/Main.swift", target: "src/domain/Store.swift",
                          relation: "imports")], totalFiles: 3, truncated: false
        )
        XCTAssertTrue(map.valid())
        let layout = ProjectTowerLayout.build(map)
        XCTAssertEqual(layout.towers.count, 3)
        XCTAssertEqual(layout.plates.map(\.name).sorted(), ["(root)", "src"])
        XCTAssertGreaterThan(layout.towers.first { $0.id == "src/domain/Store.swift" }?.height ?? 0,
                             layout.towers.first { $0.id == "src/app/Main.swift" }?.height ?? 0)
        XCTAssertNil(map.files.first { $0.path == "README.md" }?.lineCount)
        var report = ProjectRepositoryGraph(
            projectId: "p", repositoryId: "repo", revision: "sha", weavatrixVersion: "2.17.4",
            analysisStatus: "COMPLETE", nodes: [], relations: [],
            totalNodes: 0, totalRelations: 0, truncated: false
        )
        report.codeMap = map
        XCTAssertEqual(try JSONDecoder().decode(ProjectRepositoryGraph.self,
                                                from: JSONEncoder().encode(report)).codeMap, map)
        RenderProbe.render(ProjectTowersFullScreen(report: report, repositoryName: "repo", map: map))
        let invalid = ProjectCodeMap(files: map.files,
                                     roads: [.init(source: "missing", target: map.files[0].path,
                                                   relation: "imports")],
                                     totalFiles: 3, truncated: false)
        XCTAssertFalse(invalid.valid())
    }

    func testObservedEndpointBecomesInspectableApiTowerWithSourceRoad() {
        let map = ProjectCodeMap(
            files: [.init(path: "src/server.ts", language: "typescript", lineCount: 80,
                          symbols: [.init(id: "route-health", label: "GET /health",
                                          kind: "endpoint", startLine: 24, lineCount: 3)])],
            roads: [], totalFiles: 1, truncated: false
        )

        let layout = ProjectTowerLayout.build(map)
        let api = layout.towers.first { $0.id == "ext:rest-api" }
        XCTAssertEqual(api?.segments.map(\.label), ["GET /health"])
        XCTAssertEqual(layout.roads.first?.source, "src/server.ts")
        XCTAssertEqual(layout.roads.first?.target, "ext:rest-api")
        XCTAssertEqual(layout.roads.first?.relation, "exposes")
        XCTAssertEqual(layout.totalFiles, 1, "the API tower is not another source file")
    }

    func testObservedExternalResourceKeepsItsRoadAndRepositoryGrouping() throws {
        let map = ProjectCodeMap(
            files: [.init(path: "apps/api/src/server.ts", language: "typescript", lineCount: 60,
                          symbols: []),
                    .init(path: "packages/ui/src/index.ts", language: "typescript", lineCount: 12,
                          symbols: [])],
            externals: [.init(id: "ext:postgres", label: "Postgres", kind: "service")],
            roads: [.init(source: "apps/api/src/server.ts", target: "ext:postgres",
                          relation: "consumes")],
            totalFiles: 2, totalExternals: 1, truncated: false
        )
        XCTAssertTrue(map.valid())
        let decoded = try JSONDecoder().decode(ProjectCodeMap.self, from: JSONEncoder().encode(map))
        XCTAssertEqual(decoded, map)
        let layout = ProjectTowerLayout.build(decoded)
        XCTAssertEqual(layout.plates.map(\.name).sorted(), ["apps", "packages"])
        XCTAssertEqual(layout.towers.first { $0.id == "ext:postgres" }?.width, 5.2)
        XCTAssertEqual(layout.roads.first?.target, "ext:postgres")
        XCTAssertFalse(layout.towers.first { $0.id == "ext:postgres" }?.isDead ?? true)
    }
}

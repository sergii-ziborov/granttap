import Foundation
@testable import GrantTap

/// Only received source facts; absent measurements stay absent.
enum ProjectTowerViewFixtures {
    static let path = "Sources/Example.swift"
    static let externalId = "ext:storage"

    static func received<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    static func map(partial: Bool = false, measuredLOC: Int? = 410) -> ProjectCodeMap {
        let symbols = (1...36).map { index in
            ProjectCodeMap.Symbol(id: "section-\(index)", label: "section\(index)",
                kind: "method", startLine: index * 10, lineCount: index)
        }
        return ProjectCodeMap(files: [
            .init(path: path, language: "swift", lineCount: measuredLOC, symbols: symbols),
            .init(path: "README.md", language: "markdown", lineCount: nil, symbols: [])
        ], externals: [.init(id: externalId, label: "Storage", kind: "database")], roads: [
            .init(source: path, target: externalId, relation: "consumes"),
            .init(source: "README.md", target: path, relation: "documents")
        ], totalFiles: partial ? 9 : 2, totalExternals: 1, truncated: partial)
    }

    static func report(status: String? = "COMPLETE", partial: Bool = false) -> ProjectRepositoryGraph {
        var report = ProjectRepositoryGraph(projectId: "project", repositoryId: "fixture-repository",
            revision: "content-fingerprint", weavatrixVersion: "2.17.4", analysisStatus: status,
            analysisErrorCode: partial ? "incomplete_sources" : nil, nodes: [], relations: [],
            totalNodes: 4, totalRelations: 2, truncated: partial)
        report.sourceRevision = status == nil ? nil : "git-fixture-head"
        report.analysisId = "fixture-analysis"
        return report
    }

    static func largeMap() -> ProjectCodeMap {
        ProjectCodeMap(files: (0..<650).map { index in
            .init(path: "Sources/Area\(index / 25)/File\(index).swift", language: "swift",
                  lineCount: 20 + index, symbols: [])
        }, roads: [], totalFiles: 653, truncated: true)
    }
}
